import Foundation
import FandyHardware

/// Only presentation reuses this observation. Every command/admission and active
/// watchdog still performs its original fresh exclusive-controller check.
final class ControllerPresenceObservation {
    private let clock: () -> Double
    private let inspect: () throws -> Void
    private var checkedAt: Double?
    private var failure: String?
    init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         inspect: @escaping () throws -> Void = { try RecoveryOwnershipProbe.requireNoKnownController() }) {
        self.clock = clock; self.inspect = inspect
    }
    func requireExclusive() throws {
        do { try inspect(); checkedAt = clock(); failure = nil }
        catch { checkedAt = clock(); failure = error.localizedDescription; throw error }
    }
    func statusBlocker() -> String? {
        let now = clock()
        if checkedAt.map({ now.isFinite && now >= $0 && now - $0 <= 0.5 }) != true {
            do { try requireExclusive() } catch { }
        }
        return failure
    }
}
