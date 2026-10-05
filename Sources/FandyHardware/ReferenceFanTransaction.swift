import Foundation
import FandyCore

/// Reference-supported transaction. Injected reads, transport, clock and cancellation
/// exercise the production sequence in tests without changing physical hardware.
public enum ReferenceFanTransaction {
    public static let acquisitionBudget = 7.0
    public static func apply(_ targets: [FanTarget], interface: FanInterface, transport: any SMCStructTransport,
        clock: () -> Double, read: (String) throws -> DiscoveredSensor, fans: () throws -> [Fan],
        requiresForceTestOwnership: Bool = false, check: () throws -> Void, pause: () -> Void) throws {
        guard !interface.locallyTested, interface.supportsTargets else { throw ControlError.hardwareUnqualified }
        let baseline = try fans(), deadline = clock() + acquisitionBudget
        guard deadline.isFinite, baseline.map(\.id).sorted() == interface.fanIDs,
              Set(targets.map(\.fanID)) == Set(interface.fanIDs), targets.count == baseline.count else { throw ControlError.invalidFan }
        for fan in baseline { try fan.validate() }
        for target in targets {
            guard let fan = baseline.first(where: { $0.id == target.fanID }), target.rpm.isFinite,
                  target.rpm > 0, target.rpm >= fan.minimumRPM, target.rpm <= fan.maximumRPM else { throw ControlError.invalidFan }
            try interface.validateTarget(read("F\(fan.id)Tg"), id: fan.id)
        }
        var handoverOwned = requiresForceTestOwnership
        func current() throws {
            try check()
            if handoverOwned {
                let flag = try read("Ftst"); try FanInterface.validateFlag(flag)
                guard flag.value == 1 else { throw ControlError.restorationUnverified }
            }
            guard clock().isFinite, clock() < deadline else { throw ControlError.staleSession }
        }
        try current()
        let entering = baseline.contains { $0.mode.isAutomatic }
        if interface.forceTestAvailable {
            let flag = try read("Ftst"); try FanInterface.validateFlag(flag)
            guard flag.value == (handoverOwned ? 1 : 0), !entering || !handoverOwned else { throw ControlError.restorationUnverified }
            // Direct mode is attempted first, as described by the pinned references.
            // Only the known protected-command rejection admits the reviewed Ftst path.
        }
        var unlockNeeded = false
        for fan in baseline where fan.mode.isAutomatic {
            try current()
            if fan.mode == .system { unlockNeeded = true; break }
            do { try interface.startManual(id: fan.id, metadata: read(interface.modeKeys[fan.id]!), transport: transport) }
            catch RecoveryWriteError.rejected(_, let result, _) where result == 0x82 && interface.forceTestAvailable {
                unlockNeeded = true; break
            }
        }
        if unlockNeeded {
            // A partial direct admission is released before the global handover.
            for id in interface.fanIDs {
                let mode = try read(interface.modeKeys[id]!); try interface.validateMode(mode, id: id)
                if mode.value == 1 { try interface.restoreMode(id: id, metadata: mode, transport: transport) }
            }
            try current()
            try interface.writeForceTest(true, metadata: read("Ftst"), transport: transport)
            handoverOwned = true
            try FanHandover.awaitAutomatic(ids: interface.fanIDs, deadline: deadline, clock: clock, cancelled: current,
                read: { id in
                    let mode = try read(interface.modeKeys[id]!); try interface.validateMode(mode, id: id)
                    guard let value = SMCDecoder.fanMode(type: mode.type, bytes: mode.bytes) else { throw HardwareError.invalidMetadata }
                    return value
                }, pause: pause)
            for id in interface.fanIDs {
                try current()
                try interface.startManual(id: id, metadata: read(interface.modeKeys[id]!), transport: transport)
            }
        }
        // Accepted writes can become visible asynchronously on M2 firmware.
        // Poll readback within the existing admission deadline; never rewrite
        // modes or send a target until every fan independently acknowledges.
        var admitted = try fans()
        while true {
            try current()
            guard admitted.count == baseline.count, admitted.allSatisfy({ fan in
                (fan.mode == .automatic || fan.mode == .manual) && baseline.contains {
                    $0.id == fan.id && $0.minimumRPM == fan.minimumRPM && $0.maximumRPM == fan.maximumRPM
                }
            }) else { throw ControlError.restorationUnverified }
            if admitted.allSatisfy({ $0.mode == .manual }) { break }
            pause()
            admitted = try fans()
        }
        guard admitted.count == baseline.count, admitted.allSatisfy({ fan in
            fan.mode == .manual && baseline.contains { $0.id == fan.id && $0.minimumRPM == fan.minimumRPM && $0.maximumRPM == fan.maximumRPM }
        }) else { throw ControlError.restorationUnverified }
        for target in targets {
            try current()
            guard let fan = try fans().first(where: { $0.id == target.fanID }), fan.mode == .manual,
                  baseline.contains(where: { $0.id == fan.id && $0.minimumRPM == fan.minimumRPM && $0.maximumRPM == fan.maximumRPM }) else { throw ControlError.invalidFan }
            try interface.writeTarget(target, fan: fan, metadata: read("F\(fan.id)Tg"), transport: transport)
            try RecoveryTargetReadback.awaitTarget(target, baseline: fan, deadline: deadline, clock: clock,
                read: { try current(); guard let fresh = try fans().first(where: { $0.id == fan.id }) else { throw ControlError.invalidFan }; return fresh }, pause: pause)
        }
        try current()
    }
}
