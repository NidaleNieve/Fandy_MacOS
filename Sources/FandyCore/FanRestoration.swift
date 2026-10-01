import Foundation
public protocol FanHardwareIO: Sendable {
    func enumerateFans() throws -> [Fan]
    func fanIDsForRestoration() throws -> [Int]
    func setAutomatic(fanID: Int) throws
    func setManual(fanID: Int) throws
    func setTarget(fanID: Int, rpm: Double) throws
    func readMode(fanID: Int) throws -> FanMode
    func applyValidatedTargets(_ targets: [FanTarget]) throws
}
public extension FanHardwareIO {
    func fanIDsForRestoration() throws -> [Int] { try enumerateFans().map(\.id) }
    func applyValidatedTargets(_ targets: [FanTarget]) throws {
        for target in targets {
            try setManual(fanID: target.fanID)
            guard try readMode(fanID: target.fanID) == .manual else { throw ControlError.restorationUnverified }
            try setTarget(fanID: target.fanID, rpm: target.rpm)
        }
    }
}
public enum FanRestoration {
    /// Attempt every independently known fan. No target clearing or alternate mode/key guesses.
    public static func report(using io: any FanHardwareIO) throws -> RestorationReport {
        let ids = try io.fanIDsForRestoration()
        guard !ids.isEmpty, ids.count <= 8, ids.allSatisfy({ (0..<8).contains($0) }), Set(ids).count == ids.count else { throw ControlError.invalidFan }
        var outcomes: [FanRestorationOutcome] = []
        for id in ids {
            var failure: String?
            var initial: FanMode?
            do { initial = try io.readMode(fanID: id) } catch { failure = error.localizedDescription }
            var commandSucceeded = false
            do { try io.setAutomatic(fanID: id); commandSucceeded = true } catch { failure = failure ?? error.localizedDescription }
            var mode: FanMode?
            do {
                mode = try io.readMode(fanID: id)
                if mode != .automatic { failure = failure ?? ControlError.restorationUnverified.localizedDescription }
            } catch { failure = failure ?? error.localizedDescription }
            outcomes.append(FanRestorationOutcome(fanID: id, initialMode: initial, commandSucceeded: commandSucceeded,
                                                  immediateMode: mode, observedMode: mode, failure: failure))
        }
        // A second readback catches ownership changes while restoring the other fan.
        for index in outcomes.indices {
            do {
                let mode = try io.readMode(fanID: outcomes[index].fanID)
                outcomes[index].observedMode = mode
                if mode != .automatic { outcomes[index].failure = outcomes[index].failure ?? ControlError.restorationUnverified.localizedDescription }
            } catch { outcomes[index].failure = outcomes[index].failure ?? error.localizedDescription }
        }
        return RestorationReport(fans: outcomes)
    }
    public static func restore(using io: any FanHardwareIO) throws {
        guard try report(using: io).verified else { throw ControlError.restorationUnverified }
    }
    public static func apply(_ targets: [FanTarget], using io: any FanHardwareIO) throws {
        let fans = try io.enumerateFans()
        guard targets.count == fans.count, Set(targets.map(\.fanID)) == Set(fans.map(\.id)), Set(targets.map(\.fanID)).count == targets.count else { throw ControlError.invalidFan }
        // Validate the complete transaction before issuing any write.
        for target in targets {
            guard let fan = fans.first(where: { $0.id == target.fanID }), target.rpm.isFinite, target.rpm >= fan.minimumRPM, target.rpm <= fan.maximumRPM else { throw ControlError.invalidFan }
        }
        do {
            try io.applyValidatedTargets(targets)
        } catch {
            // A failed write can have applied. Never assume unchanged hardware.
            try? restore(using: io)
            throw error
        }
    }
}

public struct FanRestorationOutcome: Codable, Sendable, Equatable {
    public var fanID: Int
    public var initialMode: FanMode? = nil
    public var commandSucceeded: Bool? = nil
    public var immediateMode: FanMode? = nil
    public var observedMode: FanMode?
    public var failure: String?
    public var verified: Bool { failure == nil && commandSucceeded == true && immediateMode == .automatic && observedMode == .automatic }
    public var releasedManual: Bool { verified && initialMode == .manual }
}
public struct RestorationReport: Codable, Sendable, Equatable {
    public var fans: [FanRestorationOutcome]
    public var verified: Bool { !fans.isEmpty && fans.allSatisfy(\.verified) }
}
