import Foundation
import FandyCore
import FandyHardware
import IOKit
import os

/// Private writer in the helper executable only. No arbitrary keys are accepted over IPC.
final class AppleFanHardware: FanHardwareIO, @unchecked Sendable {
    private let commandLog = Logger(subsystem: "is.dsr.fandy", category: "fan-transaction")
    private let reader: SMCReader
    private let connection: io_connect_t
    init() throws {
        reader = try SMCReader()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw HardwareError.invalidMetadata }; defer { IOObjectRelease(service) }
        var port: io_connect_t = 0
        let result = IOServiceOpen(service,mach_task_self_,0,&port)
        guard result == KERN_SUCCESS else { throw HardwareError.smc(result) }; connection = port
    }
    deinit { IOServiceClose(connection) }
    func enumerateFans() throws -> [Fan] {
        let fans = try reader.fans()
        guard Set(fans.map(\.id)) == Set(SensorRegistry.observedFanIDs) else { throw ControlError.invalidFan }
        return fans
    }
    func fanIDsForRestoration() throws -> [Int] {
        guard HardwareSnapshotReader.machineModel() == SensorRegistry.model else { throw ControlError.hardwareUnqualified }
        // Model-scoped topology independently observed in discovery. Corrupt RPM/ranges/count
        // must not prevent a release attempt. New models need their own qualified topology.
        return SensorRegistry.observedFanIDs
    }
    func readMode(fanID: Int) throws -> FanMode {
        let value = try reader.read(qualifiedModeKey(fanID))
        guard let mode = SMCDecoder.fanMode(type: value.type, bytes: value.bytes) else { throw HardwareError.invalidMetadata }; return mode
    }
    func setAutomatic(fanID: Int) throws {
        guard SensorRegistry.capabilities.canRestore, HardwareSnapshotReader.machineModel() == SensorRegistry.model else { throw ControlError.hardwareUnqualified }
        let key = try qualifiedModeKey(fanID), mode = try reader.read(key)
        guard mode.type == "ui8 ", mode.size == 1, mode.bytes.count == 1 else { throw HardwareError.invalidMetadata }
        try SMCAutomaticModeWriter.restore(fanID: fanID, metadata: mode, transport: self)
    }
    // No independent mode/target primitive is exposed; production writes are validated batches.
    func setManual(fanID: Int) throws { throw ControlError.hardwareUnqualified }
    func setTarget(fanID: Int, rpm: Double) throws { throw ControlError.hardwareUnqualified }
    func normalizedTargets(_ targets: [FanTarget]) throws -> [FanTarget] {
        try SMCProfileWriter.normalizedTargets(targets, fans: enumerateFans())
    }
    func applyValidatedTargets(_ targets: [FanTarget]) throws {
        guard SensorRegistry.capabilities.forMachine(HardwareSnapshotReader.machineModel()).canControl else { throw ControlError.hardwareUnqualified }
        try RecoveryOwnershipProbe.requireNoKnownController()
        let baseline = try enumerateFans()
        guard targets.count == baseline.count, Set(targets.map(\.fanID)) == Set(baseline.map(\.id)),
              targets.allSatisfy({ target in baseline.contains {
                  $0.id == target.fanID && target.rpm.isFinite && target.rpm >= $0.minimumRPM && target.rpm <= $0.maximumRPM &&
                  ([.curveQualification, .qualifiedControl].contains(SensorRegistry.capabilities.stage) || target.rpm == $0.maximumRPM)
              } }) else { throw ControlError.invalidFan }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        for target in targets {
            try requireProfileDeadline(deadline)
            guard let fan = try enumerateFans().first(where: { $0.id == target.fanID }),
                  let original = baseline.first(where: { $0.id == target.fanID }),
                  fan.minimumRPM == original.minimumRPM, fan.maximumRPM == original.maximumRPM else { throw ControlError.invalidFan }
            if fan.mode == .automatic {
                commandLog.notice("Automatic admission fan \(fan.id): actual \(fan.actualRPM), previous target \(fan.targetRPM ?? -1), requested \(target.rpm)")
                try SMCProfileWriter.startAutomatic(fan: fan, mode: reader.read(qualifiedModeKey(fan.id)),
                    previous: profileTargetMetadata(fan), transport: self)
                guard let fresh = try enumerateFans().first(where: { $0.id == target.fanID }), fresh.mode == .manual else { throw ControlError.restorationUnverified }
            }
        }
        // Establish and verify both modes before either target write. This keeps the
        // mode transition phase separate from the target phase of the reviewed batch.
        for target in targets {
            try requireProfileDeadline(deadline)
            guard let fan = try enumerateFans().first(where: { $0.id == target.fanID }),
                  let original = baseline.first(where: { $0.id == target.fanID }),
                  fan.minimumRPM == original.minimumRPM, fan.maximumRPM == original.maximumRPM else { throw ControlError.invalidFan }
            guard fan.mode == .manual else { throw ControlError.invalidFan }
            try requireProfileDeadline(deadline)
            // Each admitted controller update refreshes the actual SMC target command.
            // A matching register value alone is not evidence of continuing actuation.
            try SMCProfileWriter.target(target, fan: fan, metadata: profileTargetMetadata(fan), transport: self)
            try awaitProfileTarget(target, baseline: fan, deadline: deadline, mode: .manual)
        }
    }
    private func profileTargetMetadata(_ fan: Fan) throws -> DiscoveredSensor {
        let metadata = try reader.read("F\(fan.id)Tg")
        if metadata.type != "flt " || metadata.size != 4 || metadata.attributes != 212 || metadata.value != fan.targetRPM {
            commandLog.error("Target metadata changed for fan \(fan.id): type \(metadata.type, privacy: .public), size \(metadata.size), attributes \(metadata.attributes), sampled target \(fan.targetRPM ?? -1), metadata target \(metadata.value ?? -1)")
        }
        return metadata
    }
    private func awaitProfileTarget(_ target: FanTarget, baseline: Fan, deadline: Double, mode: FanMode) throws {
        try RecoveryTargetReadback.awaitTarget(target, baseline: baseline, deadline: deadline,
            clock: { ProcessInfo.processInfo.systemUptime }, read: { [self] in
                try requireProfileDeadline(deadline)
                guard let fan = try enumerateFans().first(where: { $0.id == target.fanID }) else { throw ControlError.invalidFan }
                return fan
            }, pause: { Thread.sleep(forTimeInterval: 0.01) }, mode: mode)
        try requireProfileDeadline(deadline)
    }
    private func requireProfileDeadline(_ deadline: Double) throws {
        guard SensorRegistry.capabilities.forMachine(HardwareSnapshotReader.machineModel()).canControl,
              ProcessInfo.processInfo.systemUptime < deadline else { throw ControlError.staleSession }
        try RecoveryOwnershipProbe.requireNoKnownController()
    }
    func prepareRecoveryTarget(_ target: FanTarget, deadline: Double) throws {
        try requireRecoveryDeadline(deadline)
        guard let fan = try enumerateFans().first(where: { $0.id == target.fanID }) else { throw ControlError.invalidFan }
        let metadata = try reader.read("F\(target.fanID)Tg")
        try requireRecoveryDeadline(deadline)
        try SMCRecoveryWriter.prepare(target: target, fan: fan, metadata: metadata, transport: self)
        try requireRecoveryDeadline(deadline)
    }
    func activateRecoveryFan(_ target: FanTarget, deadline: Double) throws {
        try requireRecoveryDeadline(deadline)
        let mode = try reader.read(qualifiedModeKey(target.fanID)), prepared = try reader.read("F\(target.fanID)Tg")
        try requireRecoveryDeadline(deadline)
        try SMCRecoveryWriter.activate(target: target, mode: mode, prepared: prepared, transport: self)
        try requireRecoveryDeadline(deadline)
    }
    func startStoppedRecoveryFan(_ target: FanTarget, deadline: Double) throws {
        try requireRecoveryDeadline(deadline)
        guard let fan = try enumerateFans().first(where: { $0.id == target.fanID }) else { throw ControlError.invalidFan }
        let mode = try reader.read(qualifiedModeKey(target.fanID)), previous = try reader.read("F\(target.fanID)Tg")
        try requireRecoveryDeadline(deadline)
        try SMCRecoveryWriter.startStopped(target: target, fan: fan, mode: mode, previous: previous, transport: self)
        try requireRecoveryDeadline(deadline)
        guard let fresh = try enumerateFans().first(where: { $0.id == target.fanID }) else { throw ControlError.invalidFan }
        let metadata = try reader.read("F\(target.fanID)Tg")
        try requireRecoveryDeadline(deadline)
        try SMCRecoveryWriter.targetStartedStopped(target: target, fan: fresh, metadata: metadata, transport: self)
        try requireRecoveryDeadline(deadline)
        try RecoveryTargetReadback.awaitTarget(target, baseline: fresh, deadline: deadline,
            clock: { ProcessInfo.processInfo.systemUptime }, read: { [self] in
                try requireRecoveryDeadline(deadline)
                guard let observed = try enumerateFans().first(where: { $0.id == target.fanID }) else { throw ControlError.invalidFan }
                return observed
            }, pause: { Thread.sleep(forTimeInterval: 0.01) })
        try requireRecoveryDeadline(deadline)
    }
    private func requireRecoveryDeadline(_ deadline: Double) throws {
        guard SensorRegistry.capabilities.forMachine(HardwareSnapshotReader.machineModel()).canQualifyRecovery,
              deadline.isFinite, ProcessInfo.processInfo.systemUptime < deadline else { throw ControlError.staleSession }
    }
    private func qualifiedModeKey(_ id: Int) throws -> String {
        guard let key = SensorRegistry.observedModeKeys[id] else { throw ControlError.invalidFan }
        return key
    }
    func transact(_ input: [UInt8]) throws -> SMCStructResponse {
        guard geteuid() == 0, SensorRegistry.capabilities.forMachine(HardwareSnapshotReader.machineModel()).canRestore,
              input.count == 80 else { throw ControlError.unauthorized }
        var output = [UInt8](repeating: 0, count: 80)
        var outputSize = 80
        let result = input.withUnsafeBytes { source in output.withUnsafeMutableBytes { destination in
            IOConnectCallStructMethod(connection, 2, source.baseAddress, 80, destination.baseAddress, &outputSize)
        }}
        guard result == KERN_SUCCESS else { throw HardwareError.smc(result) }
        return SMCStructResponse(bytes: output, count: outputSize)
    }
}
extension AppleFanHardware: SMCStructTransport {}
extension AppleFanHardware: RecoveryFanHardwareIO {}
