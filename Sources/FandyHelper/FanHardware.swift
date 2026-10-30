import Foundation
import FandyCore
import FandyHardware
import IOKit
import os

/// Private writer in the helper executable only. No arbitrary keys are accepted over IPC.
final class AppleFanHardware: FanHardwareIO, @unchecked Sendable {
    private let commandLog = Logger(subsystem: "is.dsr.fandy", category: "fan-transaction")
    private let reader: SMCReader
    let cancellation: HardwareOperationFence
    private(set) var device: ResolvedDevice
    // Written only on the serial hardware queue; captured at authenticated ingress.
    var admittedOperation: HardwareOperationFence.Token?
    private var interface: FanInterface? { device.fanInterface }
    private var sampler: HardwareSnapshotReader?
    private var ownsForceTest = false
    private var transactionToken: HardwareOperationFence.Token?
    private(set) var transitions: [FanTransition] = []
    private var controlRequirements: Set<SensorRole> = []
    init(cancellation: HardwareOperationFence = HardwareOperationFence(), reader injectedReader: SMCReader? = nil, identity: DeviceIdentity = .current) throws {
        self.cancellation = cancellation
        let session = try injectedReader ?? SMCReader(transport: NativeSMCTransport(allowWrites: true))
        reader = session
        device = DeviceRegistry.resolveFans(identity: identity, read: session.read)
    }
    func resolveSensors() throws -> HardwareSnapshotReader {
        device = DeviceRegistry.resolveSensors(device: device, read: reader.read)
        let source = try HardwareSnapshotReader(device: device, reader: reader)
        sampler = source
        return source
    }
    func metadataReport() -> [FanMetadataReport] {
        let ids: [Int]
        if let interface { ids = interface.fanIDs }
        else {
            // Diagnostic-only discovery: readable metadata is not write authority.
            guard let count = try? reader.read("FNum"), count.type == "ui8 ", count.bytes.count == 1,
                  (1...2).contains(count.bytes[0]) else { return [] }
            ids = Array(0..<Int(count.bytes[0]))
        }
        return ids.map { id in
            let key = interface?.modeKeys[id]
            let mode = key.flatMap { try? reader.read($0) } ?? (try? reader.read("F\(id)md")) ?? (try? reader.read("F\(id)Md"))
            let target = try? reader.read("F\(id)Tg")
            var report = FanMetadataReport(id: id)
            report.modeKey = key ?? mode?.key; report.modeType = mode?.type; report.modeAttributes = mode?.attributes
            report.targetType = target?.type; report.targetAttributes = target?.attributes
            report.minimumRPM = (try? reader.read("F\(id)Mn"))?.value
            report.maximumRPM = (try? reader.read("F\(id)Mx"))?.value
            return report
        }
    }
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
        if !interface.locallyTested && !interface.forceTestAvailable {
            try FanHandover.awaitRelease(deadline: ProcessInfo.processInfo.systemUptime + 1,
                clock: { ProcessInfo.processInfo.systemUptime }, read: { [self] in try readMode(fanID: fanID) },
                pause: { Thread.sleep(forTimeInterval: 0.05) })
        }
    }
    func verifiedAutomaticMode(fanID: Int) throws -> FanMode {
        if interface?.locallyTested == false {
            try FanHandover.awaitRelease(deadline: ProcessInfo.processInfo.systemUptime + 1,
                clock: { ProcessInfo.processInfo.systemUptime }, read: { [self] in try readMode(fanID: fanID) },
                pause: { Thread.sleep(forTimeInterval: 0.05) })
        }
        return try readMode(fanID: fanID)
    }
    func restorationNeedsWrite(fanID: Int, mode: FanMode) -> Bool { interface?.locallyTested == true || !mode.isAutomatic }
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
        guard let sampler else { throw ControlError.invalidSnapshot }
        try ReferenceFanTransaction.apply(targets, interface: interface, transport: self,
            clock: { ProcessInfo.processInfo.systemUptime }, read: { [reader] in try reader.read($0) },
            fans: { [self] in try enumerateFans() }, requiresForceTestOwnership: ownsForceTest, check: { [self] in
                try cancellation.require(token)
                try RecoveryOwnershipProbe.requireNoKnownController()
                let snapshot = try sampler.snapshot(), now = ProcessInfo.processInfo.systemUptime
                try snapshot.validate(now: now, required: controlRequirements)

            }, cancelled: { [self] in try cancellation.require(token) }, pause: { Thread.sleep(forTimeInterval: 0.05) })
        if interface.forceTestAvailable {
            let flag = try reader.read("Ftst"); try FanInterface.validateFlag(flag)
            ownsForceTest = flag.value == 1
        }
    }
    func applyValidatedTargets(_ targets: [FanTarget]) throws {
        try applyValidatedTargets(targets, fans: enumerateFans())
    }
    func applyValidatedTargets(_ targets: [FanTarget], fans baseline: [Fan]) throws {
        guard device.capabilities.canControl, let interface else { throw ControlError.hardwareUnqualified }
        if !interface.locallyTested { try applyReferenceTargets(targets, interface: interface); return }
        transactionToken = admittedOperation ?? cancellation.token()
        defer { transactionToken = nil }
        try RecoveryOwnershipProbe.requireNoKnownController()
        guard targets.count == baseline.count, Set(targets.map(\.fanID)) == Set(baseline.map(\.id)),
              targets.allSatisfy({ target in baseline.contains {
                  $0.id == target.fanID && target.rpm.isFinite && target.rpm >= $0.minimumRPM && target.rpm <= $0.maximumRPM &&
                  ([.curveQualification, .qualifiedControl].contains(device.capabilities.stage) || target.rpm == $0.maximumRPM)
              } }) else { throw ControlError.invalidFan }
        try DirectFanTransaction.apply(targets, transport: self, read: reader.read,
            fans: { [self] in try enumerateFans() }, clock: { ProcessInfo.processInfo.systemUptime },
            check: { [self] in try requireProfileDeadline(ProcessInfo.processInfo.systemUptime + 2) },
            event: { [self] record in
                transitions.append(record); transitions = Array(transitions.suffix(16))
                commandLog.notice("Fan transition \(record.fanID): \(record.stage.rawValue, privacy: .public) at \(record.at), previous target \(record.previousTarget ?? -1), requested \(record.requestedTarget), actual \(record.actualRPM)")
            }, preflightFans: baseline)
    }

    private func requireProfileDeadline(_ deadline: Double) throws {
        if let transactionToken { try cancellation.require(transactionToken) }
        guard device.capabilities.canControl,
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
        return try reader.transact(input)
    }
}
extension AppleFanHardware: SMCStructTransport {}
extension AppleFanHardware: RecoveryFanHardwareIO {}
