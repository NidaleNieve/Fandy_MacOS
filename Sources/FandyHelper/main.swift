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
    var timer: DispatchSourceTimer?
    var power: PowerNotifications?
    init(hardware: AppleFanHardware, sampler: HardwareSnapshotReader) {
        let events = Logger(subsystem: FandyIdentity.logSubsystem, category: "safety")
        coordinator = HelperCoordinator(io: hardware, capabilities: SensorRegistry.capabilities.forMachine(HardwareSnapshotReader.machineModel()), read: { try sampler.snapshot() }, clock: { ProcessInfo.processInfo.systemUptime }, event: { message in events.notice("\(message, privacy: .public)") })
        super.init(); listener.delegate = self
    }
    func run() throws {
        guard geteuid() == 0 else { throw ControlError.unauthorized }
        listener.setConnectionCodeSigningRequirement(try PeerRequirement.make(team: ownSigningTeam(), identifier: FandyIdentity.appIdentifier))
        // Startup never resurrects a target or a lease from disk.
        queue.sync { _ = coordinator.startup() }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(500))
        source.setEventHandler { [weak self] in self?.coordinator.watchdog() }
        source.resume(); timer = source
        // Root launch daemons use IOPM notifications; the helper does not depend on GUI sleep messages.
        power = try PowerNotifications(queue: queue, coordinator: coordinator)
        logger.notice("Helper ready; restoration qualification: \(SensorRegistry.capabilities.canRestore), manual qualification: \(SensorRegistry.capabilities.canControl)")
        listener.activate(); RunLoop.current.run()
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        let object = HelperConnection(service: self)
        connection.exportedInterface = NSXPCInterface(with: FanHelperXPC.self)
        connection.exportedObject = object
        connection.invalidationHandler = { [self] in queue.async { [self] in coordinator.disconnected(owner: object.owner) } }
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
    var limiter = MessageRateLimiter()
    init(service: HelperService) { self.service = service }
    private func allowed() -> Bool { limiter.allow(at: ProcessInfo.processInfo.systemUptime) }
    func status(withReply reply: @escaping (Data?, String?) -> Void) {
        let callback = DataReply(reply)
        service.queue.async { [self] in
            guard allowed() else { service.coordinator.reject(owner: owner); callback.call(nil, ControlError.excessiveMessages.localizedDescription); return }
            do { callback.call(try Wire.encode(service.coordinator.status()), nil) } catch { callback.call(nil, error.localizedDescription) }
        }
    }
    func beginLease(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        let callback = DataReply(reply)
        service.queue.async { [self] in
            do {
                guard allowed() else { throw ControlError.excessiveMessages }
                callback.call(try Wire.encode(service.coordinator.begin(Wire.decode(LeaseRequest.self, from: data), owner: owner)), nil)
            } catch { service.coordinator.reject(owner: owner); callback.call(nil, error.localizedDescription) }
        }
    }
    func applyTargets(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        let callback = DataReply(reply)
        service.queue.async { [self] in
            do {
                guard allowed() else { throw ControlError.excessiveMessages }
                try service.coordinator.apply(Wire.decode(TargetRequest.self, from: data), owner: owner)
                callback.call(Data(), nil)
            } catch { service.coordinator.reject(owner: owner); callback.call(nil, error.localizedDescription) }
        }
    }
    func restoreAutomatic(withReply reply: @escaping (Bool, String?) -> Void) {
        let callback = BoolReply(reply)
        // Safe release remains available even if a caller exhausted its normal message budget.
        service.queue.async { [self] in let verified = service.coordinator.restore(); callback.call(verified, verified ? nil : ControlError.restorationUnverified.localizedDescription) }
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
do { try HelperService(hardware: AppleFanHardware(), sampler: HardwareSnapshotReader()).run() } catch { FileHandle.standardError.write(Data("Fandy helper: \(error.localizedDescription)\n".utf8)); exit(1) }
