import Foundation
import Security
import ServiceManagement
import FandyCore
import FandyHardware

@MainActor final class FanXPCClient: PrivilegedFanClient {
    private var connection: NSXPCConnection?
    private var connectionToken = UUID()
    private var lease: ControlLease?
    private var latest: HelperStatus?
    private var generation: UInt64?
    private var helperGeneration: UInt64 = 0
    private var operationToken = UUID()
    private let restorationFlight = RestorationFlight()
    private func signingTeam() throws -> String {
        var own: SecCode?, code: SecStaticCode?, information: CFDictionary?
        guard SecCodeCopySelf([], &own) == errSecSuccess, let own,
              SecCodeCopyStaticCode(own, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue:kSecCSSigningInformation), &information) == errSecSuccess,
              let info=information as? [String:Any],let team=info[kSecCodeInfoTeamIdentifier as String] as? String else { throw ControlError.unauthorized }
        return team
    }
    func connect() throws -> NSXPCConnection {
        if let connection { return connection }
        let team = try signingTeam()
        let connection=NSXPCConnection(machServiceName:FandyIdentity.helperIdentifier,options:.privileged)
        connection.setCodeSigningRequirement(try PeerRequirement.make(team:team,identifier:FandyIdentity.helperIdentifier))
        connection.remoteObjectInterface=NSXPCInterface(with:FanHelperXPC.self)
        let token = UUID(); connectionToken = token; helperGeneration = 0
        connection.invalidationHandler = { [weak self] in Task { @MainActor in
            guard let self, self.connectionToken == token else { return }
            self.connection=nil; self.lease=nil; self.latest=nil; self.generation=nil; self.operationToken=UUID()
        } }
        connection.interruptionHandler=connection.invalidationHandler
        self.connection=connection;connection.resume();return connection
    }
    private func dataCall(timeout: Double = 3, _ call: (any FanHelperXPC, @escaping (Data?,String?)->Void) -> Void) async throws -> Data {
        let connection=try connect()
        return try await withCheckedThrowingContinuation { continuation in
            let gate=ReplyGate<Data>(continuation)
            DispatchQueue.main.asyncAfter(deadline:.now()+timeout) { if gate.finish(.failure(ControlError.helperUnavailable)) { connection.invalidate() } }
            guard let proxy=connection.remoteObjectProxyWithErrorHandler({ @Sendable _ in gate.finish(.failure(ControlError.helperUnavailable)) }) as? any FanHelperXPC else { gate.finish(.failure(ControlError.helperUnavailable));return }
            call(proxy) { @Sendable data,error in
                if let error { gate.finish(.failure(ControlError.invalidProfile(error))) }
                else if let data { gate.finish(.success(data)) }
                else { gate.finish(.failure(ControlError.malformedMessage)) }
            }
        }
    }
    func status() async throws -> HelperStatus {
        _ = try connect(); let token = connectionToken
        let data=try await dataCall { proxy,reply in proxy.status(withReply:reply) }
        guard token == connectionToken else { throw ControlError.staleSession }
        let status=try Wire.decode(HelperStatus.self,from:data)
        guard status.version == Wire.version else { throw ControlError.malformedMessage }
        latest=status;return status
    }
    func recovery(_ request: RecoveryTrialRequest) async throws -> RecoveryTrialStatus {
        guard DeviceRegistry.current.capabilities.canQualifyRecovery else {
            throw ControlError.hardwareUnqualified
        }
        _ = try connect(); let connectionID = connectionToken
        let token = UUID(); operationToken = token
        let data = try Wire.encode(request)
        let reply = try await dataCall { proxy, callback in proxy.qualifyRecovery(data, withReply: callback) }
        try requireCurrent(token)
        guard connectionID == connectionToken else { throw ControlError.staleSession }
        return try Wire.decode(RecoveryTrialStatus.self, from: reply)
    }
    func disconnectForRecoveryTest() {
        connectionToken = UUID(); connection?.invalidate(); connection = nil
        lease = nil; latest = nil; generation = nil; operationToken = UUID()
    }
    /// Fixed adversarial messages are sent only to a confirmed observation-only helper.
    /// No caller chooses payloads, methods, fan targets or trust requirements.
    func checkObservationProtocol() async throws -> [String] {
        guard !DeviceRegistry.current.capabilities.canRestore, !DeviceRegistry.current.capabilities.canControl else { throw ControlError.unauthorized }
        return try await checkRestrictedProtocol(observationOnly: true)
    }
    func checkRestorationProtocol() async throws -> [String] {
        guard [.restorationQualification, .recoveryQualification].contains(DeviceRegistry.current.capabilities.stage),
              DeviceRegistry.current.capabilities.canRestore, !DeviceRegistry.current.capabilities.canControl,
              !DeviceRegistry.current.capabilities.canQualifyManual else { throw ControlError.unauthorized }
        return try await checkRestrictedProtocol(observationOnly: false)
    }
    /// Production-safe negative checks: no valid lease or target request is transmitted.
    func checkProductionProtocol() async throws -> [String] {
        let initial = try await status()
        guard DeviceRegistry.current.capabilities.stage == .qualifiedControl,
              initial.capabilities?.stage == .qualifiedControl, initial.automaticVerified,
              initial.manualQualified, initial.recovery?.active != true else { throw ControlError.unauthorized }
        var checks = ["authenticatedStatus"]
        do {
            for probe in try ProductionSecurityProbe.cases() {
                try await Task.sleep(for: .milliseconds(500))
                do {
                    _ = try await dataCall { proxy, reply in
                        switch probe.method {
                        case .begin: proxy.beginLease(probe.data, withReply: reply)
                        case .targets: proxy.applyTargets(probe.data, withReply: reply)
                        case .recovery: proxy.qualifyRecovery(probe.data, withReply: reply)
                        }
                    }
                    throw ControlError.unauthorized
                } catch ControlError.invalidProfile { checks.append(probe.name + "Rejected") }
            }
            disconnectForRecoveryTest()
            guard try await status().automaticVerified else { throw ControlError.restorationUnverified }
            checks.append("reconnectedStatus")
            try await checkWrongHelperIdentity(); checks.append("wrongHelperIdentityRejected")
            guard try await status().automaticVerified else { throw ControlError.restorationUnverified }
            return checks
        } catch {
            try? await restoreAutomatic()
            throw error
        }
    }
    private func checkRestrictedProtocol(observationOnly: Bool) async throws -> [String] {
        let initial = try await status()
        guard initial.observationOnly == observationOnly, !initial.manualQualified,
              initial.capabilities?.stage == DeviceRegistry.current.capabilities.stage, initial.recovery?.active != true else { throw ControlError.unauthorized }
        var checks = ["authenticatedStatus"]
        let leases: [(String, Data)] = [
            ("malformedJSON", Data("not JSON".utf8)),
            ("oversizedJSON", Data(repeating: 32, count: Wire.maxBytes + 1)),
            ("unknownRole", Data("{\"version\":2,\"generation\":1,\"required\":[\"notASensor\"]}".utf8)),
            ("generationOverflow", Data("{\"version\":2,\"generation\":18446744073709551616,\"required\":[]}".utf8)),
            ("unqualifiedLease", try Wire.encode(LeaseRequest(generation: 1, required: SensorRole.safety)))
        ]
        for (name, data) in leases {
            try await Task.sleep(for: .milliseconds(300))
            do {
                _ = try await dataCall { proxy, reply in proxy.beginLease(data, withReply: reply) }
                throw ControlError.unauthorized
            } catch ControlError.invalidProfile {
                checks.append(name + "Rejected")
            }
        }
        let forgedTarget = try Wire.encode(TargetRequest(leaseID: UUID(), generation: 1, snapshotID: UUID(), targets: [FanTarget(Int.max, 30_001)]))
        try await Task.sleep(for: .milliseconds(300))
        do {
            _ = try await dataCall(timeout: 9) { proxy, reply in proxy.applyTargets(forgedTarget, withReply: reply) }
            throw ControlError.unauthorized
        } catch ControlError.invalidProfile { checks.append("forgedTargetRejected") }
        if observationOnly {
            do { try await restoreAutomatic(); throw ControlError.unauthorized }
            catch ControlError.restorationUnverified { checks.append("observationRestoreRejected") }
        }
        // Test recovery using a fresh XPC connection, never a stale cached response.
        connectionToken = UUID(); connection?.invalidate(); connection = nil; latest = nil; lease = nil
        let reconnected = try await status()
        guard reconnected.observationOnly == observationOnly, !reconnected.manualQualified, reconnected.snapshot != nil else { throw ControlError.helperUnavailable }
        checks.append("reconnectedStatus")
        try await checkWrongHelperIdentity()
        checks.append("wrongHelperIdentityRejected")
        _ = try await status()
        return checks
    }
    private func checkWrongHelperIdentity() async throws {
        let wrong = NSXPCConnection(machServiceName: FandyIdentity.helperIdentifier, options: .privileged)
        wrong.remoteObjectInterface = NSXPCInterface(with: FanHelperXPC.self)
        wrong.setCodeSigningRequirement(try PeerRequirement.make(team: signingTeam(), identifier: FandyIdentity.helperIdentifier + ".incorrect"))
        wrong.resume(); defer { wrong.invalidate() }
        let rejected: Bool = try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate<Bool>(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { gate.finish(.failure(ControlError.helperUnavailable)) }
            guard let proxy = wrong.remoteObjectProxyWithErrorHandler({ @Sendable error in
                let error = error as NSError
                // FoundationErrors.h declares NSXPCConnectionCodeSigningRequirementFailure=4102
                // (macOS13+); the current Swift overlay does not expose a named Code member.
                if error.domain == NSCocoaErrorDomain && error.code == 4102 {
                    gate.finish(.success(true))
                } else {
                    gate.finish(.failure(ControlError.invalidProfile("Unexpected helper-identity error: \(error.domain) \(error.code)")))
                }
            }) as? any FanHelperXPC else { gate.finish(.failure(ControlError.helperUnavailable)); return }
            proxy.status { @Sendable _, _ in gate.finish(.success(false)) }
        }
        guard rejected else { throw ControlError.unauthorized }
    }
    func apply(_ targets: [FanTarget], generation: UInt64) async throws {
        try await apply(targets,generation:generation,required:DeviceRegistry.current.capabilities.chipPolicy.required)
    }
    func apply(_ targets: [FanTarget], generation requested: UInt64, required: Set<SensorRole>) async throws {
        guard DeviceRegistry.current.capabilities.permits(required: required) else { throw ControlError.hardwareUnqualified }
        let token = UUID(); operationToken = token
        if generation != requested || lease == nil {
            var status = try await status()
            try requireCurrent(token)
            if DeviceRegistry.current.capabilities.stage == .qualifiedControl, let current = lease,
               LeaseContinuation.permits(current, status: status, required: required, now: ProcessInfo.processInfo.systemUptime) {
                // Editing or changing a profile with the same required inputs keeps the
                // valid hardware lease. UI generations still fence stale acknowledgements.
                generation = requested
            } else {
                lease = nil; generation = nil
                // Fresh verified automatic ownership needs no duplicate release transaction.
                if !LeaseAdmission.automaticAlreadyVerified(status, now: ProcessInfo.processInfo.systemUptime) {
                    try await requestRestore(token: token)
                    try requireCurrent(token)
                    status = try await self.status()
                }
                try requireCurrent(token)
                guard status.automaticVerified, status.manualQualified, !status.observationOnly, let snapshot = status.snapshot else { throw ControlError.restorationUnverified }
                try snapshot.validate(now: ProcessInfo.processInfo.systemUptime, required: required)
                guard helperGeneration < UInt64.max else { throw ControlError.staleSession }
                helperGeneration += 1
                let request = try Wire.encode(LeaseRequest(generation: helperGeneration, required: required))
                let data = try await dataCall { proxy, reply in proxy.beginLease(request, withReply: reply) }
                try requireCurrent(token)
                let received = try Wire.decode(ControlLease.self, from: data)
                guard received.generation == helperGeneration, received.required == required else { throw ControlError.staleSession }
                lease = received; generation = requested
            }
        }
        let snapshot: HardwareSnapshot
        if let issued = TargetObservation.snapshot(latest, now: ProcessInfo.processInfo.systemUptime, required: required) {
            snapshot = issued
        } else {
            guard let fresh = try await status().snapshot else { throw ControlError.helperUnavailable }
            snapshot = fresh
        }
        try requireCurrent(token)
        guard let lease else { throw ControlError.helperUnavailable }
        let request = try Wire.encode(TargetRequest(leaseID: lease.id, generation: lease.generation, snapshotID: snapshot.id, targets: targets))
        _ = try await dataCall(timeout: 9) { proxy, reply in proxy.applyTargets(request, withReply: reply) }
        try requireCurrent(token)
    }
    private func requireCurrent(_ token: UUID) throws {
        guard operationToken == token else { throw ControlError.staleSession }
    }
    func restoreAutomatic() async throws {
        let token = UUID(); operationToken = token
        lease = nil; generation = nil
        try await requestRestore(token: token)
    }
    private func requestRestore(token: UUID) async throws {
        try await restorationFlight.run { [self] in try await sendRestore() }
        try requireCurrent(token)
    }
    private func sendRestore() async throws {
        let connection = try connect()
        let verified: Bool = try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate<Bool>(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if gate.finish(.failure(ControlError.helperUnavailable)) { connection.invalidate() } }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable _ in gate.finish(.failure(ControlError.helperUnavailable)) }) as? any FanHelperXPC else { gate.finish(.failure(ControlError.helperUnavailable)); return }
            proxy.restoreAutomatic { @Sendable verified, error in
                if verified && error == nil { gate.finish(.success(true)) } else { gate.finish(.failure(ControlError.restorationUnverified)) }
            }
        }
        guard verified else { throw ControlError.restorationUnverified }
    }

}
/// Exactly-once completion also covers timeout and XPC invalidation races.
private final class ReplyGate<T: Sendable>: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<T,any Error>?
    init(_ continuation:CheckedContinuation<T,any Error>) { self.continuation=continuation }
    @discardableResult func finish(_ result:Result<T,any Error>) -> Bool {
        lock.lock();let pending=continuation;continuation=nil;lock.unlock()
        pending?.resume(with:result)
        return pending != nil
    }
}
@MainActor enum HelperManager {
    static var service:SMAppService { .daemon(plistName:FandyIdentity.launchDaemonPlist) }
    static var installed:Bool { service.status == .enabled }
    private static var legacyService: SMAppService { .daemon(plistName: FandyIdentity.legacyLaunchDaemonPlist) }
    /// Older development registrations retain validation category 3 after an
    /// upgrade to Developer ID (category 6), even across unregister/register.
    /// Remove that registration before creating the distribution service; the
    /// XPC name, helper signing identity and caller authentication stay fixed.
    static func migrateLegacyService(client: FanXPCClient) async throws {
        try requireInstalledLocation()
        guard legacyService.status == .enabled || legacyService.status == .requiresApproval else { return }
        if legacyService.status == .enabled {
            do { try await client.restoreAutomatic() }
            catch ControlError.helperUnavailable { /* Dead legacy job: replacement startup must verify release. */ }
        }
        try await unregister(service: legacyService)
        client.disconnectForRecoveryTest()
    }
    static func install() throws {
        guard legacyService.status != .enabled && legacyService.status != .requiresApproval else { throw ControlError.helperUnavailable }
        guard DeviceRegistry.current.capabilities.canRestore else { throw ControlError.hardwareUnqualified }
        try requireInstalledLocation()
        switch service.status {
        case .notRegistered, .notFound: try service.register()
        case .enabled, .requiresApproval: break
        @unknown default: throw ControlError.helperUnavailable
        }
    }
    static func installObservation() throws {
        // This path must stop working when a future build gains any physical write capability.
        guard !DeviceRegistry.current.capabilities.canRestore, !DeviceRegistry.current.capabilities.canControl else { throw ControlError.unauthorized }
        try requireInstalledLocation()
        switch service.status {
        case .notRegistered, .notFound: try service.register()
        case .enabled, .requiresApproval: break
        @unknown default: throw ControlError.helperUnavailable
        }
    }
    static func uninstallObservation(client: FanXPCClient) async throws {
        guard !DeviceRegistry.current.capabilities.canRestore, !DeviceRegistry.current.capabilities.canControl else { throw ControlError.unauthorized }
        if service.status == .enabled {
            let status = try await client.status()
            guard status.observationOnly, !status.manualQualified else { throw ControlError.unauthorized }
        }
        if service.status != .notRegistered { try await unregisterService() }
    }
    static func uninstall(client:FanXPCClient) async throws {
        try await remove(status: service.status, restore: { try await client.restoreAutomatic() },
            unregister: { try await unregisterService() })
    }
    /// Approval and availability are separate; a live registration requires handback.
    static func remove(status: SMAppService.Status, restore: () async throws -> Void,
        unregister: () async throws -> Void) async throws {
        switch status {
        case .enabled: try await restore(); try await unregister()
        case .requiresApproval: try await unregister()
        case .notRegistered, .notFound: return
        @unknown default: throw ControlError.helperUnavailable
        }
    }
    static func unregisterService() async throws { try await unregister(service: service) }
    private static func unregister(service: SMAppService) async throws {
        // Bridge the documented completion API on the main actor. macOS 15's SDK
        // does not mark SMAppService Sendable, so its actor-owned wrapper must not
        // be passed to the imported nonisolated async overload.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            service.unregister { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
        // Completion can precede publication of the new status. Do not treat a
        // stale enabled observation as a successfully registered replacement.
        for _ in 0..<50 {
            if service.status == .notRegistered || service.status == .notFound { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ControlError.helperUnavailable
    }
    private static func requireInstalledLocation() throws {
        let url = Bundle.main.bundleURL.resolvingSymlinksInPath()
        // Development builds retain the existing helper workflow. Distribution copies
        // must be installed before registration, including App Translocation paths.
        var code: SecStaticCode?, information: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess else { throw ControlError.unauthorized }
        let info = information as? [String: Any]
        let certificates = info?[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let developerID = certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }?.hasPrefix("Developer ID Application:") == true
        if developerID && url.path != "/Applications/Fandy.app" {
            throw ControlError.invalidProfile("Move Fandy to Applications, then reopen it to enable fan control.")
        }
    }
}
