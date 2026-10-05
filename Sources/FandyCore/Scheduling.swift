import Foundation

/// ISO weekday, Monday = 1. Half-open intervals; equal times are invalid, not all-day.
public struct WeeklyPeriod: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var profileID: String
    public var weekday: Int
    public var startMinute: Int
    public var endMinute: Int
    public var enabled: Bool
    public init(id: UUID = UUID(), profileID: String, weekday: Int, startMinute: Int, endMinute: Int, enabled: Bool = true) {
        self.id = id; self.profileID = profileID; self.weekday = weekday
        self.startMinute = startMinute; self.endMinute = endMinute; self.enabled = enabled
    }
    public func validate(profileIDs: Set<String>) throws {
        guard profileIDs.contains(profileID), (1...7).contains(weekday), (0..<1440).contains(startMinute),
              (0...1440).contains(endMinute), startMinute != endMinute else {
            throw ScheduleError("Invalid profile, weekday or time range.")
        }
    }
    public var spansMidnight: Bool { endMinute < startMinute }
    public var segments: [WeekSegment] {
        let start = (weekday - 1) * 1440 + startMinute
        let end = (weekday - 1) * 1440 + endMinute + (spansMidnight ? 1440 : 0)
        if end > 10080 { return [WeekSegment(start: start, end: 10080), WeekSegment(start: 0, end: end - 10080)] }
        return [WeekSegment(start: start, end: end)]
    }
}
public struct WeekSegment: Sendable, Equatable {
    public let start: Int
    public let end: Int
    public init(start: Int, end: Int) { self.start = start; self.end = end }
    public func intersection(_ other: Self) -> Self? {
        let lower = max(start, other.start), upper = min(end, other.end)
        return lower < upper ? Self(start: lower, end: upper) : nil
    }
    public func subtract(_ other: Self) -> [Self] {
        guard let overlap = intersection(other) else { return [self] }
        return [start < overlap.start ? Self(start: start, end: overlap.start) : nil,
                overlap.end < end ? Self(start: overlap.end, end: end) : nil].compactMap { $0 }
    }
}
public struct SchedulePause: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// nil pauses every scheduled profile. Manual activations always remain independent.
    public var profileID: String?
    public var start: Date
    public var end: Date
    public init(id: UUID = UUID(), profileID: String? = nil, start: Date, end: Date) {
        self.id = id; self.profileID = profileID; self.start = start; self.end = end
    }
    public func contains(_ date: Date, profile: String) -> Bool { (profileID == nil || profileID == profile) && start <= date && date < end }
}
public struct AppPreferences: Codable, Sendable, Equatable {
    public var defaultProfileID: String = "system"
    public var launchAtLogin: Bool = true
    public var use24HourTime: Bool = true
    public var showHelperProcesses: Bool = false
    public var menuSensors: [String] = []
    public var showFanSpeedBar: Bool = true
    public var showFanSpeedNumbers: Bool = true
    public var shortcuts: [String: ShortcutBinding] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey { case defaultProfileID, launchAtLogin, use24HourTime, showHelperProcesses, menuSensors, shortcuts, showFanSpeedBar, showFanSpeedNumbers }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultProfileID = try c.decodeIfPresent(String.self, forKey: .defaultProfileID) ?? "system"
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        use24HourTime = try c.decodeIfPresent(Bool.self, forKey: .use24HourTime) ?? true
        showHelperProcesses = try c.decodeIfPresent(Bool.self, forKey: .showHelperProcesses) ?? false
        showFanSpeedBar = try c.decodeIfPresent(Bool.self, forKey: .showFanSpeedBar) ?? true
        showFanSpeedNumbers = try c.decodeIfPresent(Bool.self, forKey: .showFanSpeedNumbers) ?? true
        menuSensors = try c.decodeIfPresent([String].self, forKey: .menuSensors) ?? []
        shortcuts = try c.decodeIfPresent([String: ShortcutBinding].self, forKey: .shortcuts) ?? [:]
    }
}
public struct AutomationConfiguration: Codable, Sendable, Equatable {
    public var periods: [WeeklyPeriod] = []
    public var pauses: [SchedulePause] = []
    public var preferences = AppPreferences()
    public var activationDefaults: [String: ProfileActivationDefault] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey { case periods, pauses, preferences, activationDefaults }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        periods = try c.decodeIfPresent([WeeklyPeriod].self, forKey: .periods) ?? []
        pauses = try c.decodeIfPresent([SchedulePause].self, forKey: .pauses) ?? []
        preferences = try c.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? .init()
        activationDefaults = try c.decodeIfPresent([String: ProfileActivationDefault].self, forKey: .activationDefaults) ?? [:]
    }
    public func validate(profileIDs: Set<String>, allowConflicts: Bool = false) throws {
        guard periods.count <= 1024, pauses.count <= 256, preferences.menuSensors.count <= 16,
              Set(periods.map(\.id)).count == periods.count, Set(pauses.map(\.id)).count == pauses.count,
              Set(preferences.menuSensors).count == preferences.menuSensors.count,
              preferences.menuSensors.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 100 }) else { throw ScheduleError("Configuration limit exceeded or duplicate identifiers.") }
        guard (preferences.defaultProfileID == "system" || profileIDs.contains(preferences.defaultProfileID)), Set(activationDefaults.keys).isSubset(of: profileIDs), Set(preferences.shortcuts.keys).isSubset(of: profileIDs.union(["menu"])),
              Set(preferences.shortcuts.values.map { "\($0.keyCode):\($0.modifiers)" }).count == preferences.shortcuts.count else { throw ScheduleError("Duplicate shortcuts or unknown profile preferences.") }
        try activationDefaults.values.forEach { try $0.validate() }
        try preferences.shortcuts.values.forEach { try $0.validate() }
        try periods.forEach { try $0.validate(profileIDs: profileIDs) }
        guard pauses.allSatisfy({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.start < $0.end && ($0.profileID.map { profileIDs.contains($0) } ?? true) }) else { throw ScheduleError("Pause must have a valid profile and increasing finite dates.") }
        if !allowConflicts {
            for (index, period) in periods.enumerated() where period.enabled {
                guard ScheduleEngine.conflicts(period, in: Array(periods.prefix(index))).isEmpty else { throw ScheduleError("Overlapping schedule ranges need review.") }
            }
        }
    }
}
public struct ScheduleConflict: Sendable, Equatable, Identifiable {
    public var id: UUID { incumbent.id }
    public let incumbent: WeeklyPeriod
    public let incoming: WeeklyPeriod
    public let overlaps: [WeekSegment]
}
public enum ScheduleEngine {
    public static func hasActivity(in configuration: AutomationConfiguration, after start: Date, before end: Date, calendar: Calendar = .current) -> Bool {
        guard start < end, configuration.periods.contains(where: \.enabled) else { return false }
        var day = calendar.startOfDay(for: start)
        // Temporary activations are bounded to 31 days; indefinite/process menus
        // ask about the coming week rather than assuming a termination time.
        for _ in 0..<33 {
            guard day < end, let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7
            let daySegment = WeekSegment(start: weekday * 1440, end: (weekday + 1) * 1440)
            for period in configuration.periods where period.enabled {
                for segment in period.segments {
                    guard let overlap = segment.intersection(daySegment) else { continue }
                    let low = overlap.start - daySegment.start, high = overlap.end - daySegment.start
                    guard let begin = calendar.date(bySettingHour: low / 60, minute: low % 60, second: 0, of: day),
                          let finish = high == 1440 ? nextDay : calendar.date(bySettingHour: high / 60, minute: high % 60, second: 0, of: day) else { continue }
                    let lower = max(start, begin), upper = min(end, finish)
                    guard lower < upper else { continue }
                    var portions: [(Date, Date)] = [(lower, upper)]
                    for pause in configuration.pauses where pause.profileID == nil || pause.profileID == period.profileID {
                        portions = portions.flatMap { a, b in
                            guard pause.start < b, a < pause.end else { return [(a,b)] }
                            return [a < pause.start ? (a,min(b,pause.start)) : nil, pause.end < b ? (max(a,pause.end),b) : nil].compactMap { $0 }
                        }
                    }
                    if !portions.isEmpty { return true }
                }
            }
            day = nextDay
        }
        return false
    }
    public static func conflicts(_ incoming: WeeklyPeriod, in existing: [WeeklyPeriod]) -> [ScheduleConflict] {
        guard incoming.enabled else { return [] }
        return existing.filter { $0.enabled && $0.id != incoming.id }.compactMap { period in
            let overlap = period.segments.flatMap { left in incoming.segments.compactMap { left.intersection($0) } }
            return overlap.isEmpty ? nil : ScheduleConflict(incumbent: period, incoming: incoming, overlaps: overlap)
        }
    }
    /// Override subtracts only overlapping minutes. Every non-overlapping remainder survives.
    public static func overriding(_ incoming: WeeklyPeriod, in existing: [WeeklyPeriod]) -> [WeeklyPeriod] {
        var result: [WeeklyPeriod] = []
        for period in existing where period.id != incoming.id {
            guard !conflicts(incoming, in: [period]).isEmpty else { result.append(period); continue }
            let remaining = incoming.segments.reduce(period.segments) { pieces, cut in pieces.flatMap { $0.subtract(cut) } }
            for piece in remaining {
                // Split at midnight so spillover remains visible and future edits are unambiguous.
                var cursor = piece.start
                while cursor < piece.end {
                    let end = min(piece.end, (cursor / 1440 + 1) * 1440)
                    result.append(WeeklyPeriod(profileID: period.profileID, weekday: cursor / 1440 + 1,
                                               startMinute: cursor % 1440, endMinute: end % 1440 == 0 ? 1440 : end % 1440))
                    cursor = end
                }
            }
        }
        return result + [incoming]
    }
    /// Calendar scheduling uses local wall time; DST gaps/repetitions follow Calendar components.
    /// A repeated hour is active on both occurrences. Temporary durations use a separate clock.
    public static func active(in config: AutomationConfiguration, at date: Date, calendar: Calendar = .current) -> WeeklyPeriod? {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let day = components.weekday, let hour = components.hour, let minute = components.minute else { return nil }
        let isoDay = (day + 5) % 7
        let weekMinute = isoDay * 1440 + hour * 60 + minute
        return config.periods.first { period in
            period.enabled && period.segments.contains { $0.start <= weekMinute && weekMinute < $0.end }
            && !config.pauses.contains { $0.contains(date, profile: period.profileID) }
        }
    }
    public static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    public static func parseTime(_ text: String, allowEndOfDay: Bool = false) throws -> Int {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let hours = Int(parts[0]), let minutes = Int(parts[1]), minutes < 60,
              hours < 24 || (allowEndOfDay && hours == 24 && minutes == 0) else { throw ScheduleError("Expected HH:mm in 24-hour time (00:00–23:59).") }
        return hours * 60 + minutes
    }
}
public struct ScheduleError: Error, LocalizedError, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Runtime intent is deliberately absent from Codable archives. Startup/wake never restore it.
public struct ActivationIntent: Sendable, Equatable {
    public enum Limit: Sendable, Equatable {
        case forever
        case deadline(Date)
        case process(pid: Int32, launched: Date)
    }
    public let profileID: String
    public let limit: Limit
    public init(profileID: String, limit: Limit = .forever) { self.profileID = profileID; self.limit = limit }
    public func expired(at date: Date, running: (Int32, Date) -> Bool) -> Bool {
        switch limit {
        case .forever: false
        case .deadline(let end): date >= end
        case .process(let pid, let launched): !running(pid, launched)
        }
    }
}
