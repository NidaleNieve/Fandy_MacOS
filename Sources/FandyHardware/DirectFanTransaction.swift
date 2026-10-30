import Foundation
import FandyCore

/// Reviewed direct codec with all reads and writes injected. Preflight every fan;
/// keep mode admission and that fan's target adjacent before admitting another fan.
public enum DirectFanTransaction {
    /// Read-only heartbeat verification. Never admits a mode or writes a target.
    public static func verifyAcknowledged(_ targets: [FanTarget], baseline: [Fan],
        read: (String) throws -> DiscoveredSensor, fans: () throws -> [Fan], check: () throws -> Void) throws -> Bool {
        try check()
        _ = try SMCProfileWriter.normalizedTargets(targets, fans: baseline)
        for fan in baseline {
            let mode = try read("F\(fan.id)md")
            guard fan.mode == .manual, mode.type == "ui8 ", mode.size == 1, mode.attributes == 208,
                  mode.bytes == [1], mode.value == 1, mode.error == nil else { throw HardwareError.invalidMetadata }
            let target = try read("F\(fan.id)Tg")
            try SMCProfileWriter.validateTargetMetadata(target, fan: fan)
            guard let expected = targets.first(where: { $0.fanID == fan.id }), target.value == expected.rpm else { throw ControlError.restorationUnverified }
        }
        let observed = try fans()
        guard observed.count == baseline.count, Set(observed.map(\.id)) == Set(baseline.map(\.id)) else { throw ControlError.invalidFan }
        for fan in observed {
            try fan.validate()
            guard fan.mode == .manual, let old = baseline.first(where: { $0.id == fan.id }),
                  fan.minimumRPM == old.minimumRPM, fan.maximumRPM == old.maximumRPM,
                  fan.targetRPM == targets.first(where: { $0.fanID == fan.id })?.rpm else { throw ControlError.restorationUnverified }
        }
        try check()
        return true
    }
    public static func apply(_ targets: [FanTarget], transport: any SMCStructTransport,
        read: (String) throws -> DiscoveredSensor, fans: () throws -> [Fan],
        clock: () -> Double, check: () throws -> Void,
        event: (FanTransition) -> Void = { _ in }, preflightFans: [Fan]? = nil) throws {
        let baseline = try preflightFans ?? fans(), deadline = clock() + 2
        guard deadline.isFinite else { throw ControlError.invalidNumber }
        _ = try SMCProfileWriter.normalizedTargets(targets, fans: baseline)
        var modes: [Int: DiscoveredSensor] = [:], metadata: [Int: DiscoveredSensor] = [:]
        for fan in baseline {
            let mode = try read("F\(fan.id)md")
            guard mode.type == "ui8 ", mode.size == 1, mode.attributes == 208,
                  mode.value == Double(fan.mode.rawValue), mode.error == nil,
                  mode.bytes == [UInt8(fan.mode.rawValue)], fan.mode == .automatic || fan.mode == .manual else { throw HardwareError.invalidMetadata }
            modes[fan.id] = mode
            let previous = try read("F\(fan.id)Tg")
            try SMCProfileWriter.validateTargetMetadata(previous, fan: fan); metadata[fan.id] = previous
        }
        func requireLive() throws {
            try check(); guard clock().isFinite, clock() < deadline else { throw ControlError.staleSession }
        }
        for target in targets {
            guard var fan = baseline.first(where: { $0.id == target.fanID }), let mode = modes[fan.id], let previous = metadata[fan.id] else { throw ControlError.invalidFan }
            let entering = fan.mode == .automatic
            // No admission or target operation exists for an already acknowledged
            // value. Complete metadata preflight above and independent batch
            // ownership/readback below still run on every request.
            if !entering && previous.value == target.rpm { continue }
            func record(_ stage: FanTransition.Stage) {
                if entering { event(FanTransition(fanID: fan.id, stage: stage, at: clock(), actualRPM: fan.actualRPM, previousTarget: fan.targetRPM, requestedTarget: target.rpm)) }
            }
            if entering {
                try requireLive()
                try SMCProfileWriter.startAutomatic(fan: fan, mode: mode, previous: previous, transport: transport)
                record(.modeWritten)
                let observed = try read("F\(fan.id)md")
                guard observed.type == mode.type, observed.size == mode.size, observed.attributes == mode.attributes,
                      observed.bytes == [1], observed.value == 1, observed.error == nil else { throw ControlError.restorationUnverified }
                fan.mode = .manual
            }
            try requireLive()
            if entering || previous.value != target.rpm {
                try SMCProfileWriter.target(target, fan: fan, metadata: previous, transport: transport)
                record(.targetWritten)
            }
        }
        // One fresh inventory acknowledges the complete batch. Repeating a full
        // inventory separately for each fan adds I/O without independent evidence.
        let start = clock(), limit = min(deadline, start + 0.5)
        guard start.isFinite, start < limit else { throw ControlError.staleSession }
        var previous = start
        while true {
            try requireLive()
            let before = clock(), observed = try fans(), now = clock()
            guard now.isFinite, now >= before, now >= previous, now < deadline, now <= limit else { throw ControlError.staleSession }
            previous = now
            guard observed.count == baseline.count, Set(observed.map(\.id)) == Set(baseline.map(\.id)) else { throw ControlError.invalidFan }
            var complete = true
            for target in targets {
                guard let old = baseline.first(where: { $0.id == target.fanID }),
                      let fan = observed.first(where: { $0.id == target.fanID }) else { throw ControlError.invalidFan }
                try fan.validate()
                guard fan.mode == .manual, fan.minimumRPM == old.minimumRPM, fan.maximumRPM == old.maximumRPM,
                      let actual = fan.targetRPM, actual.isFinite else { throw ControlError.invalidFan }
                if abs(actual - target.rpm) > 0.5 {
                    guard actual == 0 || actual == old.targetRPM, now < limit else {
                        throw RecoveryTrialError.targetMismatch(fanID: fan.id, expected: target.rpm, observed: actual)
                    }
                    complete = false
                }
            }
            if complete {
                try requireLive()
                for target in targets {
                    if let fan = baseline.first(where: { $0.id == target.fanID }), fan.mode == .automatic {
                        event(FanTransition(fanID: fan.id, stage: .acknowledged, at: clock(), actualRPM: fan.actualRPM, previousTarget: fan.targetRPM, requestedTarget: target.rpm))
                    }
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}
