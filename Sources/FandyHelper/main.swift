import Foundation
import FandyCore
import FandyHardware
import Security
import os

/// Listener lifetime is independent of hardware availability. Only ready backends admit leases.
final class HelperService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let listener = NSXPCListener(machServiceName: FandyIdentity.helperIdentifier)
    let queue = DispatchQueue(label: "is.dsr.fandy.helper.safety", qos: .userInitiated)
    let logger = Logger(subsystem: FandyIdentity.logSubsystem, category: "helper")
    let requests = HelperRequestGate()
    let cancellation = HardwareOperationFence()
    private(set) var coordinator: HelperCoordinator?
    private(set) var recovery: RecoveryTrialCoordinator?
    private var releaseCoordinator: HelperCoordinator?
    private var hardware: AppleFanHardware?
    private var bootstrap = HelperBootstrapStatus()
    private var retry = HelperBootstrapRetry()
    private var startedAt: Double = 0
    private var powerAvailable = true
    private var powerSuspended = false
    var timer: DispatchSourceTimer?
    var power: PowerNotifications?
    override init() { super.init(); listener.delegate = self }
    func run() throws {
        guard geteuid() == 0 else { throw ControlError.unauthorized }
        listener.setConnectionCodeSigningRequirement(try PeerRequirement.make(team: ownSigningTeam(), identifier: FandyIdentity.appIdentifier))
        // Authentication is established before listener publication; SMC failure cannot kill status.
        listener.activate()
        startedAt = ProcessInfo.processInfo.systemUptime
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(100))
        source.setEventHandler { [weak self] in self?.watchdog() }
        source.resume(); timer = source
        do {
            power = try PowerNotifications(queue: DispatchQueue(label: "is.dsr.fandy.helper.power")) { [self] transition in
                cancellation.cancel()
                queue.sync { [self] in
                    switch transition {
                    case .willSleep:
                        guard !powerSuspended else { return }
                        powerSuspended = true
                        _ = recovery?.release(reason: "System sleep")
                        releaseCoordinator?.systemWillSleep()
                        timer?.schedule(deadline: .distantFuture)
                    case .didWake:
                        guard powerSuspended else { return }
                        releaseCoordinator?.systemDidWake(); powerSuspended = false
                        timer?.schedule(deadline: .now(), repeating: .milliseconds(100))
                    }
                }
            }
        } catch { powerAvailable = false }
        // Release still runs when notification setup fails; control stays unavailable.
        queue.async { [self] in bootstrapAttempt() }
        RunLoop.current.run()
    }
    private func bootstrapAttempt() {
        guard !powerSuspended else { return }
        guard retry.beginAttempt() else { return }
        bootstrap = .init(attempt: retry.attempts)
        do {
            let hardware = try AppleFanHardware(cancellation: cancellation)
            self.hardware = hardware
            let events = Logger(subsystem: FandyIdentity.logSubsystem, category: "safety")
            var sampler: HardwareSnapshotReader?
            let control = HelperCoordinator(io: hardware, capabilities: hardware.device.capabilities,
                read: { guard let sampler else { throw ControlError.helperUnavailable }; return try sampler.snapshot() },
                clock: { ProcessInfo.processInfo.systemUptime }, event: { events.notice("\($0, privacy: .public)") },
                requireExclusive: { try RecoveryOwnershipProbe.requireNoKnownController() })
            releaseCoordinator = control
            bootstrap.stage = .restoring
            if hardware.device.capabilities.canRestore { guard control.startup() else { throw ControlError.restorationUnverified } }
            guard powerAvailable else { throw BootstrapFailure.powerNotifications }
            // Automatic restoration precedes temperature-reader construction.
            sampler = try HardwareSnapshotReader(device: hardware.device)
            let source = RecoverySampleSource(sampler: sampler!)
            let recovery = RecoveryTrialCoordinator(io: hardware, capabilities: hardware.device.capabilities,
                read: { try source.read() }, clock: { ProcessInfo.processInfo.systemUptime },
                restore: { _ = control.restore(); return control.lastRestoration },
                requireExclusive: { try RecoveryOwnershipProbe.requireNoKnownController() })
            self.coordinator = control; self.recovery = recovery
            bootstrap = .init(stage: .ready, attempt: retry.attempts)
            logger.notice("Helper backend ready")
        } catch {
            bootstrap = .init(stage: .failed, attempt: retry.attempts, failureCode: Self.failureCode(error))
            logger.error("Helper bootstrap failed: \(self.bootstrap.failureCode ?? "unknown", privacy: .public)")
            let transient: Bool
            if case HardwareError.smc(let code) = error { transient = UInt32(bitPattern: code) != 0xFAD00084 }
            else { transient = false }
            if let offset = retry.nextOffset(transient: transient) {
                queue.asyncAfter(deadline: .now() + max(0, startedAt + offset - ProcessInfo.processInfo.systemUptime)) { [self] in bootstrapAttempt() }
            }
        }
    }
    private enum BootstrapFailure: Error { case powerNotifications }
    private static func failureCode(_ error: Error) -> String {
        if error is BootstrapFailure { return "power_notifications" }
        if case HardwareError.smc(let code) = error { return "smc_" + String(UInt32(bitPattern: code), radix: 16) }
        if case HardwareError.invalidMetadata = error { return "unsupported_metadata" }
        if case ControlError.restorationUnverified = error { return "restoration_unverified" }
        if case ControlError.unauthorized = error { return "authentication" }
        return "backend_initialization"
    }
    func status() -> HelperStatus {
        var status: HelperStatus
        if let coordinator { status = coordinator.status(); status.recovery = recovery?.status }
        else {
            status = HelperStatus(automaticVerified: false, observationOnly: true,
                fault: "Fan helper could not start", capabilities: hardware?.device.capabilities,
                restoration: releaseCoordinator?.lastRestoration, startupRestoration: releaseCoordinator?.lastRestoration)
        }
        if let interface = hardware?.device.fanInterface {
            status.fanInterface = HelperFanInterface(modeKeys: interface.fanIDs.compactMap { interface.modeKeys[$0] },
                targetTypes: interface.fanIDs.compactMap { interface.targetFormats[$0]?.rawValue }, forceTest: interface.forceTestAvailable)
        }
        status.bootstrap = bootstrap; status.helperBuild = FandyBuild.identifier
        if coordinator != nil && (status.capabilities?.canQualifyRecovery == true || status.capabilities?.canControl == true) {
            do { try RecoveryOwnershipProbe.requireNoKnownController() } catch { status.recoveryBlocker = error.localizedDescription }
        }
        return status
    }
    func requireCoordinator() throws -> HelperCoordinator {
        guard !powerSuspended, let coordinator, bootstrap.stage == .ready else { throw ControlError.helperUnavailable }; return coordinator
    }
    func requireRecovery() throws -> RecoveryTrialCoordinator {
        guard !powerSuspended, let recovery, bootstrap.stage == .ready else { throw ControlError.helperUnavailable }; return recovery
    }
    func restore() -> Bool {
        if let recovery { return recovery.release(reason: "System requested") }
        return releaseCoordinator?.restore() ?? false
    }
    private func watchdog() {
        guard !powerSuspended, let coordinator, let recovery, let hardware else { return }
        let owner = coordinator.leaseOwner ?? recovery.activeOwner
        do {
            hardware.admittedOperation = try owner.map { try cancellation.token(owner: $0) } ?? cancellation.token()
            defer { hardware.admittedOperation = nil }
            recovery.watchdog(); coordinator.watchdog()
        } catch { if let owner { coordinator.disconnected(owner: owner); recovery.disconnected(owner: owner) } }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        let object = HelperConnection(service: self)
        guard requests.connect(owner: object.owner) else { return false }
        guard cancellation.connect(owner: object.owner) else { _ = requests.close(owner: object.owner); requests.disconnected(owner: object.owner); return false }
        connection.exportedInterface = NSXPCInterface(with: FanHelperXPC.self)
        connection.exportedObject = object
        connection.invalidationHandler = { [self] in
            guard requests.close(owner: object.owner) else { return }
            cancellation.disconnected(owner: object.owner)
            queue.async { [self] in
                coordinator?.disconnected(owner: object.owner); recovery?.disconnected(owner: object.owner)
                requests.disconnected(owner: object.owner)
            }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume(); return true
    }
    func admit(_ token: HardwareOperationFence.Token) throws { try cancellation.require(token); hardware?.admittedOperation = token }
    func finishHardwareOperation() { hardware?.admittedOperation = nil }
}

func ownSigningTeam() throws -> String {
    var code: SecCode?, staticCode: SecStaticCode?, information: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
          SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let info = information as? [String: Any], let team = info[kSecCodeInfoTeamIdentifier as String] as? String else { throw ControlError.unauthorized }
    return team
}
final class HelperConnection: NSObject, FanHelperXPC, @unchecked Sendable {
    let owner = UUID()
    let service: HelperService
    init(service: HelperService) { self.service = service }
    private func reject() {
        guard let ticket = service.requests.rejection(owner: owner) else { return }
        service.cancellation.cancel(owner: owner)
        service.queue.async { [self] in
            defer { service.requests.finish(ticket) }
            if service.requests.isOpen(ticket) { service.coordinator?.reject(owner: owner); service.recovery?.reject(owner: owner) }
        }
    }
    private func request(bytes: Int? = nil, reply: DataReply,
                         work: @escaping @Sendable (HelperService) throws -> Data) {
        let ticket: HelperRequestGate.Ticket
        do { ticket = try service.requests.admit(owner: owner, bytes: bytes, now: ProcessInfo.processInfo.systemUptime) }
        catch { reject(); reply.call(nil, error.localizedDescription); return }
        let hardwareToken: HardwareOperationFence.Token
        do { hardwareToken = try service.cancellation.token(owner: owner) }
        catch { service.requests.finish(ticket); reply.call(nil, error.localizedDescription); return }
        service.queue.async { [self] in
            defer { service.requests.finish(ticket) }
            guard service.requests.isOpen(ticket) else { reply.call(nil, ControlError.staleSession.localizedDescription); return }
            do {
                try service.cancellation.require(hardwareToken)
                try service.admit(hardwareToken)
                defer { service.finishHardwareOperation() }
                reply.call(try work(service), nil)
            }
            catch { service.coordinator?.reject(owner: owner); service.recovery?.reject(owner: owner); reply.call(nil, error.localizedDescription) }
        }
    }
    func status(withReply reply: @escaping (Data?, String?) -> Void) {
        request(reply: DataReply(reply)) { try Wire.encode($0.status()) }
    }
    func qualifyRecovery(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        request(bytes: data.count, reply: DataReply(reply)) { [service, owner] _ in
            try Wire.encode(service.requireRecovery().request(RecoveryTrialRequest.decode(data), owner: owner))
        }
    }
    func beginLease(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        request(bytes: data.count, reply: DataReply(reply)) { [owner] service in
            try Wire.encode(service.requireCoordinator().begin(Wire.decodeCommand(LeaseRequest.self, from: data), owner: owner))
        }
    }
    func applyTargets(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        request(bytes: data.count, reply: DataReply(reply)) { [owner] service in
            try service.requireCoordinator().apply(Wire.decodeCommand(TargetRequest.self, from: data), owner: owner)
            return Data()
        }
    }
    func restoreAutomatic(withReply reply: @escaping (Bool, String?) -> Void) {
        let callback = BoolReply(reply)
        let ticket: HelperRequestGate.Ticket
        do { ticket = try service.requests.admitRestoration(owner: owner) }
        catch { callback.call(false, error.localizedDescription); return }
        service.cancellation.cancel()
        // Reserved release capacity is independent of ordinary queue/rate limits.
        service.queue.async { [self] in
            defer { service.requests.finish(ticket) }
            guard service.requests.isOpen(ticket) else { callback.call(false, ControlError.staleSession.localizedDescription); return }
            let verified = service.restore()
            callback.call(verified, verified ? nil : ControlError.restorationUnverified.localizedDescription)
        }
    }
}
private final class RecoverySampleSource {
    let sampler: HardwareSnapshotReader
    var reader: RecoveryObservationReader?
    init(sampler: HardwareSnapshotReader) { self.sampler = sampler }
    func read() throws -> RecoveryObservation {
        // No temperature enumeration precedes helper startup restoration.
        if reader == nil { reader = try RecoveryObservationReader(sampler: sampler) }
        guard let reader else { throw ControlError.invalidSnapshot }
        return try reader.observation()
    }
}
// Foundation XPC callbacks cross into our serial queue; the framework owns their thread safety.
final class DataReply: @unchecked Sendable {
    let callback: (Data?, String?) -> Void
    init(_ callback: @escaping (Data?, String?) -> Void) { self.callback = callback }
    func call(_ data: Data?, _ error: String?) { callback(data,error) }
}
final class BoolReply: @unchecked Sendable {
    let callback: (Bool, String?) -> Void
    init(_ callback: @escaping (Bool, String?) -> Void) { self.callback = callback }
    func call(_ verified: Bool, _ error: String?) { callback(verified,error) }
}
do { try HelperService().run() }
catch { FileHandle.standardError.write(Data("Fandy helper authentication or listener initialization failed.\n".utf8)); exit(1) }
