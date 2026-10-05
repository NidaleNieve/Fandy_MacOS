import Foundation
import FandyCore

/// Reviewed direct codec with all reads and writes injected. Preflight every fan;
/// keep mode admission and that fan's target adjacent before admitting another fan.
public enum DirectFanTransaction {
    public static func apply(_ targets: [FanTarget], transport: any SMCStructTransport,
        read: (String) throws -> DiscoveredSensor, fans: () throws -> [Fan],
        clock: () -> Double, check: () throws -> Void,
        event: (FanTransition) -> Void = { _ in }) throws {
        let baseline = try fans(), deadline = clock() + 2
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
            try requireLive()
            guard var fan = baseline.first(where: { $0.id == target.fanID }), let mode = modes[fan.id], let previous = metadata[fan.id] else { throw ControlError.invalidFan }
            let entering = fan.mode == .automatic
            func record(_ stage: FanTransition.Stage) {
                if entering { event(FanTransition(fanID: fan.id, stage: stage, at: clock(), actualRPM: fan.actualRPM, previousTarget: fan.targetRPM, requestedTarget: target.rpm)) }
            }
            if entering {
                try SMCProfileWriter.startAutomatic(fan: fan, mode: mode, previous: previous, transport: transport)
                record(.modeWritten)
                let observed = try read("F\(fan.id)md")
                guard observed.type == mode.type, observed.size == mode.size, observed.attributes == mode.attributes,
                      observed.bytes == [1], observed.value == 1, observed.error == nil else { throw ControlError.restorationUnverified }
                fan.mode = .manual
            }
            try requireLive()
            try SMCProfileWriter.target(target, fan: fan, metadata: previous, transport: transport)
            record(.targetWritten)
        }
        // No repeated fan enumeration between admissions: target every fan promptly,
        // then perform full acknowledgement while all requested modes are established.
        for target in targets {
            guard var fan = baseline.first(where: { $0.id == target.fanID }) else { throw ControlError.invalidFan }
            let entering = fan.mode == .automatic; fan.mode = .manual
            try RecoveryTargetReadback.awaitTarget(target, baseline: fan, deadline: deadline, clock: clock,
                read: { try requireLive(); guard let value = try fans().first(where: { $0.id == fan.id }) else { throw ControlError.invalidFan }; return value }, pause: { Thread.sleep(forTimeInterval: 0.01) })
            if entering { event(FanTransition(fanID: fan.id, stage: .acknowledged, at: clock(), actualRPM: fan.actualRPM, previousTarget: fan.targetRPM, requestedTarget: target.rpm)) }
        }
        try requireLive()
        let final = try fans()
        guard final.count == baseline.count, final.allSatisfy({ fan in
            fan.mode == .manual && baseline.contains { $0.id == fan.id && $0.minimumRPM == fan.minimumRPM && $0.maximumRPM == fan.maximumRPM }
        }) else { throw ControlError.invalidFan }
    }
}
