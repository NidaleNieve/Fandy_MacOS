import Foundation
import FandyCore
import FandyHardware
import Security
import os

final class HelperService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let listener = NSXPCListener(machServiceName: FandyIdentity.helperIdentifier)
    let queue = DispatchQueue(label: "is.dsr.fandy.helper.safety", qos: .userInitiated)
    let logger = Logger(subsystem: FandyIdentity.logSubsystem, category: "helper")
    let coordinator: HelperCoordinator
    let recovery: RecoveryTrialCoordinator
    let requests = HelperRequestGate()
    let hardware: AppleFanHardware
    var timer: DispatchSourceTimer?
    var power: PowerNotifications?
    init(hardware: AppleFanHardware, sampler: HardwareSnapshotReader) {
        self.hardware = hardware
        let events = Logger(subsystem: FandyIdentity.logSubsystem, category: "safety")
        let capabilities = sampler.device.capabilities
        let control = HelperCoordinator(io: hardware, capabilities: capabilities, read: { try sampler.snapshot() }, clock: { ProcessInfo.processInfo.systemUptime }, event: { message in events.notice("\(message, privacy: .public)") },
            requireExclusive: { try RecoveryOwnershipProbe.requireNoKnownController() })
        coordinator = control
        let source = RecoverySampleSource(sampler: sampler)
        recovery = RecoveryTrialCoordinator(io: hardware, capabilities: capabilities, read: { try source.read() },
            clock: { ProcessInfo.processInfo.systemUptime }, restore: { _ = control.restore(); return control.lastRestoration },
            requireExclusive: { try RecoveryOwnershipProbe.requireNoKnownController() })
        super.init(); listener.delegate = self
    }
    func run() throws {
        guard geteuid() == 0 else { throw ControlError.unauthorized }
        listener.setConnectionCodeSigningRequirement(try PeerRequirement.make(team: ownSigningTeam(), identifier: FandyIdentity.appIdentifier))
        // Startup never resurrects a target or a lease from disk.
        queue.sync { _ = coordinator.startup() }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(100))
        source.setEventHandler { [weak self] in self?.watchdog() }
        source.resume(); timer = source
        // Root launch daemons use IOPM notifications; the helper does not depend on GUI sleep messages.
        power = try PowerNotifications(queue: DispatchQueue(label: "is.dsr.fandy.helper.power")) { [self] in
            hardware.cancellation.cancel()
            queue.sync { [self] in
                _ = recovery.release(reason: "sleep/wake")
                coordinator.powerTransition()
            }
        }
        logger.notice("Helper ready; restoration qualification: \(DeviceRegistry.current.capabilities.canRestore), manual qualification: \(DeviceRegistry.current.capabilities.canControl)")
        listener.activate(); RunLoop.current.run()
    }
    private func watchdog() {
        let owner = coordinator.leaseOwner ?? recovery.activeOwner
        do {
            hardware.admittedOperation = try owner.map { try hardware.cancellation.token(owner: $0) } ?? hardware.cancellation.token()
            defer { hardware.admittedOperation = nil }
            recovery.watchdog(); coordinator.watchdog()
        } catch {
            if let owner { coordinator.disconnected(owner: owner); recovery.disconnected(owner: owner) }
        }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        let object = HelperConnection(service: self)
        guard requests.connect(owner: object.owner) else { return false }
        guard hardware.cancellation.connect(owner: object.owner) else {
            _ = requests.close(owner: object.owner); requests.disconnected(owner: object.owner)
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: FanHelperXPC.self)
        connection.exportedObject = object
        connection.invalidationHandler = { [self] in
            guard requests.close(owner: object.owner) else { return }
            hardware.cancellation.disconnected(owner: object.owner)
            queue.async { [self] in
                coordinator.disconnected(owner: object.owner)
                recovery.disconnected(owner: object.owner)
                requests.disconnected(owner: object.owner)
            }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume(); return true
    }
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
        service.hardware.cancellation.cancel(owner: owner)
        service.queue.async { [self] in
            defer { service.requests.finish(ticket) }
            if service.requests.isOpen(ticket) { service.coordinator.reject(owner: owner); service.recovery.reject(owner: owner) }
        }
    }
    private func request(bytes: Int? = nil, reply: DataReply,
                         work: @escaping @Sendable (HelperCoordinator) throws -> Data) {
        let ticket: HelperRequestGate.Ticket
        do { ticket = try service.requests.admit(owner: owner, bytes: bytes, now: ProcessInfo.processInfo.systemUptime) }
        catch { reject(); reply.call(nil, error.localizedDescription); return }
        let hardwareToken: HardwareOperationFence.Token
        do { hardwareToken = try service.hardware.cancellation.token(owner: owner) }
        catch { service.requests.finish(ticket); reply.call(nil, error.localizedDescription); return }
        service.queue.async { [self] in
            defer { service.requests.finish(ticket) }
            guard service.requests.isOpen(ticket) else { reply.call(nil, ControlError.staleSession.localizedDescription); return }
            do {
                try service.hardware.cancellation.require(hardwareToken)
                service.hardware.admittedOperation = hardwareToken
                defer { service.hardware.admittedOperation = nil }
                reply.call(try work(service.coordinator), nil)
            }
            catch { service.coordinator.reject(owner: owner); service.recovery.reject(owner: owner); reply.call(nil, error.localizedDescription) }
        }
    }
    func status(withReply reply: @escaping (Data?, String?) -> Void) {
        request(reply: DataReply(reply)) { [service] coordinator in
            var status = coordinator.status(); status.recovery = service.recovery.status
            status.helperBuild = FandyBuild.identifier
            if status.capabilities?.canQualifyRecovery == true || status.capabilities?.canControl == true {
                do { try RecoveryOwnershipProbe.requireNoKnownController() }
                catch { status.recoveryBlocker = error.localizedDescription }
            }
            return try Wire.encode(status)
        }
    }
    func qualifyRecovery(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        request(bytes: data.count, reply: DataReply(reply)) { [service, owner] _ in
            try Wire.encode(service.recovery.request(RecoveryTrialRequest.decode(data), owner: owner))
        }
    }
    func beginLease(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        request(bytes: data.count, reply: DataReply(reply)) { [owner] coordinator in
            try Wire.encode(coordinator.begin(Wire.decodeCommand(LeaseRequest.self, from: data), owner: owner))
        }
    }
    func applyTargets(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        request(bytes: data.count, reply: DataReply(reply)) { [owner] coordinator in
            try coordinator.apply(Wire.decodeCommand(TargetRequest.self, from: data), owner: owner)
            return Data()
        }
    }
    func restoreAutomatic(withReply reply: @escaping (Bool, String?) -> Void) {
        let callback = BoolReply(reply)
        let ticket: HelperRequestGate.Ticket
        do { ticket = try service.requests.admitRestoration(owner: owner) }
        catch { callback.call(false, error.localizedDescription); return }
        service.hardware.cancellation.cancel()
        // Reserved release capacity is independent of ordinary queue/rate limits.
        service.queue.async { [self] in
            defer { service.requests.finish(ticket) }
            guard service.requests.isOpen(ticket) else { callback.call(false, ControlError.staleSession.localizedDescription); return }
            let verified = service.recovery.release(reason: "System requested")
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
do {
    let hardware = try AppleFanHardware()
    // Release precedes sensor resolution, including restart with Ftst still asserted.
    if (try? hardware.fanIDsForRestoration()) != nil { try FanRestoration.restore(using: hardware) }
    try HelperService(hardware: hardware, sampler: HardwareSnapshotReader()).run()
} catch { FileHandle.standardError.write(Data("Fandy helper: \(error.localizedDescription)\n".utf8)); exit(1) }
