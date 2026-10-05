import Foundation

/// Shared with the signed helper. Release verification checks this against Info.plist.
public enum FandyBuild {
    public static let version = "0.2.3"
    public static let identifier = "17"
}

public enum UpdateFrequency: String, Codable, Sendable, CaseIterable, Identifiable {
    case never, daily, weekly, monthly
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var interval: TimeInterval? {
        switch self {
        case .never: nil
        case .daily: 86_400
        case .weekly: 604_800
        case .monthly: 2_592_000
        }
    }
}

public struct UpdatePolicy: Equatable, Sendable {
    public static let reminderInterval: TimeInterval = 1_209_600
    public let automatic: Bool
    public let frequency: UpdateFrequency
    public init(_ preferences: AppPreferences) {
        automatic = preferences.automaticUpdates
        frequency = preferences.updateFrequency
    }
    public var checksEnabled: Bool { automatic && frequency != .never }
    public var interval: TimeInterval { frequency.interval ?? UpdateFrequency.weekly.interval! }
    public func checkIsDue(lastCheck: Date?, now: Date) -> Bool {
        checksEnabled && (lastCheck.map { now.timeIntervalSince($0) >= interval } ?? true)
    }
    public static func reminderIsDue(downloadedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(downloadedAt) >= reminderInterval
    }
}

/// A single verified preparation shared by relaunch and normal quit paths.
/// A failure never authorizes installation; subsequent attempts may retry.
@MainActor public final class UpdatePreparation {
    public private(set) var ready = false
    private var flight: Task<Void, Error>?
    private let operation: @MainActor () async throws -> Void
    public init(operation: @escaping @MainActor () async throws -> Void) { self.operation = operation }
    public func prepare() async throws {
        if ready { return }
        if let flight { try await flight.value; return }
        let task = Task { try await operation() }; flight = task
        defer { flight = nil }
        do { try await task.value; ready = true }
        catch { ready = false; throw error }
    }
}
