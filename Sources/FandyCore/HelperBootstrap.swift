import Foundation

public struct HelperBootstrapStatus: Codable, Sendable, Equatable {
    public enum Stage: String, Codable, Sendable { case initializing, restoring, ready, failed }
    public var stage: Stage
    public var attempt: Int
    public var failureCode: String?
    public init(stage: Stage = .initializing, attempt: Int = 0, failureCode: String? = nil) {
        self.stage = stage; self.attempt = attempt; self.failureCode = failureCode
    }
}

/// Fixed retry policy; no caller supplies timing or can create a restart loop.
public struct HelperBootstrapRetry: Sendable {
    private(set) public var attempts = 0
    public init() {}
    public mutating func beginAttempt() -> Bool {
        guard attempts < 3 else { return false }; attempts += 1; return true
    }
    public func nextOffset(transient: Bool) -> Double? {
        guard transient else { return nil }
        return attempts == 1 ? 1 : attempts == 2 ? 3 : nil
    }
}

public struct HelperFanInterface: Codable, Sendable, Equatable {
    public let modeKeys: [String]
    public let targetTypes: [String]
    public let forceTest: Bool
    public init(modeKeys: [String], targetTypes: [String], forceTest: Bool) {
        self.modeKeys = modeKeys; self.targetTypes = targetTypes; self.forceTest = forceTest
    }
}

public struct FanTransition: Codable, Sendable, Equatable {
    public enum Stage: String, Codable, Sendable { case modeWritten, targetWritten, acknowledged }
    public let fanID: Int
    public let stage: Stage
    public let at: Double
    public let actualRPM: Double
    public let previousTarget: Double?
    public let requestedTarget: Double
    public init(fanID: Int, stage: Stage, at: Double, actualRPM: Double, previousTarget: Double?, requestedTarget: Double) {
        self.fanID = fanID; self.stage = stage; self.at = at; self.actualRPM = actualRPM
        self.previousTarget = previousTarget; self.requestedTarget = requestedTarget
    }
}
