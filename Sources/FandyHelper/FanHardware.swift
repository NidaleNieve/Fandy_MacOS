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
    let cancellation = HardwareOperationFence()
    // Written only on the serial hardware queue; captured at authenticated ingress.
    var admittedOperation: HardwareOperationFence.Token?
    private let interface: FanInterface?
    private var ownsForceTest = false
    private var transactionToken: HardwareOperationFence.Token?
    private var controlRequirements: Set<SensorRole> = []
    init() throws {
        let observationReader = try SMCReader(); reader = observationReader
        interface = try? FanInterface.discover(identity: .current, read: { try observationReader.read($0) })
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw HardwareError.invalidMetadata }; defer { IOObjectRelease(service) }
        var port: io_connect_t = 0
        let result = IOServiceOpen(service,mach_task_self_,0,&port)
        guard result == KERN_SUCCESS else { throw HardwareError.smc(result) }; connection = port
    }
    deinit { IOServiceClose(connection) }
    func enumerateFans() throws -> [Fan] {
        let fans = try reader.fans()
        guard let interface, Set(fans.map(\.id)) == Set(interface.fanIDs) else { throw ControlError.invalidFan }
        return fans
    }
    func fanIDsForRestoration() throws -> [Int] {
        guard let interface else { throw ControlError.hardwareUnqualified }
        // Model-scoped topology independently observed in discovery. Corrupt RPM/ranges/count
        // must not prevent a release attempt. New models need their own qualified topology.
        return interface.fanIDs
    }
    func readMode(fanID: Int) throws -> FanMode {
        let value = try reader.read(qualifiedModeKey(fanID))
        try interface?.validateMode(value, id: fanID)
        guard let mode = SMCDecoder.fanMode(type: value.type, bytes: value.bytes) else { throw HardwareError.invalidMetadata }; return mode
    }
    func setAutomatic(fanID: Int) throws {
        guard let interface else { throw ControlError.hardwareUnqualified }
        let key = try qualifiedModeKey(fanID), mode = try reader.read(key)
        guard mode.type == "ui8 ", mode.size == 1, mode.bytes.count == 1 else { throw HardwareError.invalidMetadata }
        try interface.restoreMode(id: fanID, metadata: mode, transport: self)
    }
    func acceptsAutomatic(_ mode: FanMode) -> Bool { interface?.locallyTested == true ? mode == .automatic : mode.isAutomatic }
    func finishAutomaticRestoration() throws {
        guard let interface else { throw ControlError.hardwareUnqualified }
        guard interface.forceTestAvailable else { return }
        let flag = try reader.read("Ftst")
        try FanInterface.validateFlag(flag)
        if flag.value != 0 { try interface.writeForceTest(false, metadata: flag, transport: self) }
        let observed = try reader.read("Ftst")
        try FanInterface.validateFlag(observed)
        guard observed.value == 0 else { throw ControlError.restorationUnverified }
        ownsForceTest = false
    }
    func setControlRequirements(_ required: Set<SensorRole>) { controlRequirements = required }
    func normalizedTargets(_ targets: [FanTarget]) throws -> [FanTarget] {
        if interface?.locallyTested == true { return try SMCProfileWriter.normalizedTargets(targets, fans: enumerateFans()) }
        let fans = try enumerateFans()
        guard targets.count == fans.count, Set(targets.map(\.fanID)) == Set(fans.map(\.id)) else { throw ControlError.invalidFan }
        return try targets.map { target in
            guard let fan = fans.first(where: { $0.id == target.fanID }), target.rpm.isFinite,
                  target.rpm >= fan.minimumRPM, target.rpm <= fan.maximumRPM else { throw ControlError.invalidFan }
            let rounded = interface?.targetFormats[fan.id] == .fixed ? ceil(target.rpm * 4) / 4 : ceil(target.rpm)
            return FanTarget(fan.id, min(fan.maximumRPM, rounded))
        }
    }
    private func applyReferenceTargets(_ targets: [FanTarget], interface: FanInterface) throws {
        let token = admittedOperation ?? cancellation.token()
        let sampler = try HardwareSnapshotReader()
        try ReferenceFanTransaction.apply(targets, interface: interface, transport: self,
            clock: { ProcessInfo.processInfo.systemUptime }, read: { [reader] in try reader.read($0) },
            fans: { [self] in try enumerateFans() }, requiresForceTestOwnership: ownsForceTest, check: { [self] in
                try cancellation.require(token)
                try RecoveryOwnershipProbe.requireNoKnownController()
                let snapshot = try sampler.snapshot(), now = ProcessInfo.processInfo.systemUptime
                try snapshot.validate(now: now, required: controlRequirements)
                if !controlRequirements.isEmpty {
                    let guardPercent = try BuiltInProfiles.guardCurve.evaluate(DeviceRegistry.current.capabilities.chipPolicy.temperature(in: snapshot, now: now))
                    guard targets.allSatisfy({ target in snapshot.fans.contains {
                        $0.id == target.fanID && target.rpm >= ((try? $0.rpm(percent: guardPercent)) ?? .infinity)
                    } }) else { throw ControlError.thermalPressure }
                }
            }, pause: { Thread.sleep(forTimeInterval: 0.05) })
        if interface.forceTestAvailable {
            let flag = try reader.read("Ftst"); try FanInterface.validateFlag(flag)
            ownsForceTest = flag.value == 1
        }
    }
    func applyValidatedTargets(_ targets: [FanTarget]) throws {
        guard DeviceRegistry.current.capabilities.canControl, let interface else { throw ControlError.hardwareUnqualified }
        if !interface.locallyTested { try applyReferenceTargets(targets, interface: interface); return }
        transactionToken = admittedOperation ?? cancellation.token()
        defer { transactionToken = nil }
        try RecoveryOwnershipProbe.requireNoKnownController()
        let baseline = try enumerateFans()
        guard targets.count == baseline.count, Set(targets.map(\.fanID)) == Set(baseline.map(\.id)),
              targets.allSatisfy({ target in baseline.contains {
                  $0.id == target.fanID && target.rpm.isFinite && target.rpm >= $0.minimumRPM && target.rpm <= $0.maximumRPM &&
                  ([.curveQualification, .qualifiedControl].contains(DeviceRegistry.current.capabilities.stage) || target.rpm == $0.maximumRPM)
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
        if let transactionToken { try cancellation.require(transactionToken) }
        guard DeviceRegistry.current.capabilities.canControl,
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
        if let admittedOperation { try cancellation.require(admittedOperation) }
        guard SensorRegistry.capabilities.forMachine(HardwareSnapshotReader.machineModel()).canQualifyRecovery,
              deadline.isFinite, ProcessInfo.processInfo.systemUptime < deadline else { throw ControlError.staleSession }
    }
    private func qualifiedModeKey(_ id: Int) throws -> String {
        guard let key = interface?.modeKeys[id] else { throw ControlError.invalidFan }
        return key
    }
    func transact(_ input: [UInt8]) throws -> SMCStructResponse {
        guard geteuid() == 0, interface != nil,
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
