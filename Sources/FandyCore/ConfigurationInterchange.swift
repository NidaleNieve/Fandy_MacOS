import Foundation
import CoreFoundation

public struct PortableConfiguration: Codable, Sendable, Equatable {
    public var version = 2
    public var profiles: [Profile]
    public var automation: AutomationConfiguration
    public init(profiles: [Profile], automation: AutomationConfiguration) { self.profiles = profiles; self.automation = automation }
    public func validate(allowConflicts: Bool = false) throws {
        guard version == 2, profiles.count <= 128, Set(profiles.map(\.id)).count == profiles.count,
              Set(BuiltInProfiles.all.map(\.id)).isSubset(of: Set(profiles.map(\.id))) else { throw ScheduleError("Configuration must retain every built-in profile and unique identifiers.") }
        try profiles.forEach { profile in
            try profile.validate()
            guard profile.bundled == BuiltInProfiles.all.contains(where: { $0.id == profile.id }) else { throw ScheduleError("Invalid built-in metadata.") }
        }
        try automation.validate(profileIDs: Set(profiles.map(\.id)), allowConflicts: allowConflicts)
    }
}
public enum ConfigurationInterchange {
    public static func encode(_ config: PortableConfiguration) throws -> Data {
        try config.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(config)
        guard bytes.count <= 1_048_576 else { throw ScheduleError("Configuration exceeds 1 MiB.") }
        return bytes
    }
    public static func decode(_ data: Data) throws -> PortableConfiguration {
        let root = try ImportValidation.root(data)
        guard Set(root.keys) == ["version", "profiles", "automation"] else { throw ScheduleError("Expected only version, profiles and automation. Runtime control authority cannot be imported.") }
        try ImportValidation.profiles(root["profiles"])
        try ImportValidation.automation(root["automation"])
        var result = try JSONDecoder().decode(PortableConfiguration.self, from: data)
        result.profiles = result.profiles.map(BuiltInProfiles.normalizeName)
        try result.validate()
        return result
    }
}
public struct ScheduledProfileBundle: Sendable {
    public var profiles: [Profile]
    public var periods: [WeeklyPeriod]
    public var pauses: [SchedulePause]
    public var replacements: [Profile] = []
    public var activationDefaults: [String: ProfileActivationDefault] = [:]
}
public enum ScheduledProfileInterchange {
    private struct Archive: Codable { let version: Int; let profiles: [Profile]; let periods: [WeeklyPeriod]; let pauses: [SchedulePause]; let activationDefaults: [String: ProfileActivationDefault]? }
    public static func encode(_ profile: Profile, automation: AutomationConfiguration) throws -> Data {
        var copy = profile.bundled ? profile : profile.duplicated(); copy.name = profile.name
        let periods = automation.periods.filter { $0.profileID == profile.id }.map { period in
            var result = period; result.profileID = copy.id; return result
        }
        let pauses = automation.pauses.filter { $0.profileID == profile.id || $0.profileID == nil }.map { pause in
            var result = pause; result.profileID = copy.id; return result
        }
        var config = AutomationConfiguration(); config.periods = periods; config.pauses = pauses
        let defaults = automation.activationDefaults[profile.id].map { [copy.id: $0] } ?? [:]
        config.activationDefaults = defaults
        try copy.validate(); try config.validate(profileIDs: [copy.id])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Archive(version: 2, profiles: [copy], periods: periods, pauses: pauses, activationDefaults: defaults))
        guard data.count <= 1_048_576 else { throw ScheduleError("Profile exceeds 1 MiB.") }; return data
    }
    public static func decode(_ data: Data, existingCount: Int) throws -> ScheduledProfileBundle {
        let root = try ImportValidation.root(data)
        if root["version"] as? Int == 1 { return ScheduledProfileBundle(profiles: try ProfileInterchange.decode(data, existingCount: existingCount), periods: [], pauses: []) }
        guard Set(root.keys).isSubset(of: ["version", "profiles", "periods", "pauses", "activationDefaults"]), Set(["version", "profiles", "periods", "pauses"]).isSubset(of: Set(root.keys)) else { throw ScheduleError("Expected version, profiles, periods and pauses.") }
        try ImportValidation.profiles(root["profiles"])
        try ImportValidation.periods(root["periods"])
        try ImportValidation.pauses(root["pauses"])
        if let defaults = root["activationDefaults"] { try ImportValidation.defaults(defaults) }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 2, !archive.profiles.isEmpty, archive.profiles.count <= 128, archive.profiles.filter({ !$0.bundled }).count <= 128 - min(max(existingCount, 0), 128),
              Set(archive.profiles.map(\.id)).count == archive.profiles.count else { throw ScheduleError("Invalid version, duplicate profiles or profile limit exceeded.") }
        try archive.profiles.forEach { profile in
            let builtin = BuiltInProfiles.all.contains(where: { $0.id == profile.id })
            guard profile.bundled == builtin else { throw ScheduleError("Invalid built-in identity.") }
            try profile.validate()
        }
        var config = AutomationConfiguration(); config.periods = archive.periods; config.pauses = archive.pauses; config.activationDefaults = archive.activationDefaults ?? [:]
        try config.validate(profileIDs: Set(archive.profiles.map(\.id)), allowConflicts: true)
        let copies = archive.profiles.map { profile -> Profile in var result = profile.bundled ? profile : profile.duplicated(); result.name = profile.name; return BuiltInProfiles.normalizeName(result) }
        let ids = Dictionary(uniqueKeysWithValues: zip(archive.profiles.map(\.id), copies.map(\.id)))
        return ScheduledProfileBundle(profiles: copies.filter { !$0.bundled }, periods: archive.periods.map { period in
            var result = period; result.id = UUID(); result.profileID = ids[period.profileID]!; return result
        }, pauses: archive.pauses.map { pause in
            var result = pause; result.id = UUID(); result.profileID = pause.profileID.flatMap { ids[$0] }; return result
        }, replacements: copies.filter(\.bundled), activationDefaults: Dictionary(uniqueKeysWithValues: (archive.activationDefaults ?? [:]).map { (ids[$0.key]!, $0.value) }))
    }
}
enum ImportValidation {
    static func fields(_ value: Any?, allowed: Set<String>, path: String) throws -> [String: Any] {
        guard let object = value as? [String: Any], Set(object.keys).isSubset(of: allowed) else { throw ScheduleError("\(path): unexpected fields or invalid object.") }
        return object
    }
    static func array(_ value: Any?, limit: Int, path: String) throws -> [[String: Any]] {
        guard let entries = value as? [[String: Any]], entries.count <= limit else { throw ScheduleError("\(path): invalid array or item limit exceeded.") }
        return entries
    }
    static func profiles(_ value: Any?) throws {
        for (index, entry) in try array(value, limit: 128, path: "profiles").enumerated() {
            _ = try fields(entry, allowed: ["id", "name", "kind", "bundled", "defaultRevision", "curves", "floor", "automaticAtIdle", "targetTemperature", "chipSources", "fanResponse"], path: "profiles[\(index)]")
            if let target = entry["targetTemperature"], !(target is NSNull) { _ = try fields(target, allowed: ["input", "celsius"], path: "targetTemperature") }
            for curve in try array(entry["curves"], limit: 4, path: "curves") {
                _ = try fields(curve, allowed: ["input", "points", "enabled"], path: "curves")
                for point in try array(curve["points"], limit: 32, path: "points") {
                    _ = try fields(point, allowed: ["id", "temperature", "percent"], path: "points")
                }
            }
        }
    }
    static func periods(_ value: Any?) throws {
        for entry in try array(value, limit: 1024, path: "periods") {
            _ = try fields(entry, allowed: ["id", "profileID", "weekday", "startMinute", "endMinute", "enabled"], path: "periods")
        }
    }
    static func pauses(_ value: Any?) throws {
        for entry in try array(value, limit: 256, path: "pauses") {
            _ = try fields(entry, allowed: ["id", "profileID", "start", "end"], path: "pauses")
        }
    }
    static func defaults(_ value: Any) throws {
        guard let defaults = value as? [String: Any], defaults.count <= 128 else { throw ScheduleError("Invalid activation defaults.") }
        for item in defaults.values {
            let object = try fields(item, allowed: ["kind", "seconds", "applicationID", "applicationName", "applications", "launchWhenOpened"], path: "activation default")
            if let entries = object["applications"] {
                for entry in try array(entries, limit: 32, path: "applications") {
                    _ = try fields(entry, allowed: ["id", "name", "kind"], path: "application")
                }
            }
        }
    }
    static func automation(_ value: Any?) throws {
        let object = try fields(value, allowed: ["periods", "pauses", "preferences", "activationDefaults"], path: "automation")
        if let value = object["activationDefaults"] { try defaults(value) }
        if let value = object["periods"] { try periods(value) }
        if let value = object["pauses"] { try pauses(value) }
        // Accept the retired clock field in old exports, but decoding drops it.
        if let value = object["preferences"] { _ = try fields(value, allowed: ["defaultProfileID", "launchAtLogin", "use24HourTime", "showClock", "showHelperProcesses", "menuSensors", "shortcuts", "showFanSpeedBar", "showFanSpeedNumbers", "automaticUpdates", "updateFrequency"], path: "preferences")
            if let shortcuts = (value as? [String: Any])?["shortcuts"] as? [String: Any] {
                for binding in shortcuts.values { _ = try fields(binding, allowed: ["keyCode", "modifiers", "key"], path: "shortcut") }
            } }
    }
    static func root(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= 1_048_576 else { throw ScheduleError("Import must be between 1 byte and 1 MiB.") }
        // Reject deep nesting before Foundation decodes it. String braces do not contribute.
        var depth = 0, quoted = false, escaped = false
        for byte in data {
            if quoted { if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 { quoted = false } }
            else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 { depth += 1; if depth > 32 { throw ScheduleError("JSON nesting exceeds 32 levels.") } }
            else if byte == 125 || byte == 93 { depth -= 1; if depth < 0 { throw ScheduleError("Unbalanced JSON nesting.") } }
        }
        guard depth == 0, !quoted, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ScheduleError("Expected a JSON object.") }
        return root
    }
}

/// Human-friendly schema is distinct from stored UUID/minute-based rules.
public enum ScheduleTextImport {
    public static func prompt(profiles: [Profile]) -> String {
        """
        Format my schedule as JSON only, without Markdown fences. Fandy schema:
        {"version":1,"entries":[{"profile":"Silent","day":"Monday","start":"08:30","end":"12:30"}],"pauses":[{"profile":"Silent","start":"2026-12-20T00:00:00Z","end":"2027-01-04T00:00:00Z"}]}
        Use exactly these profile names: \(profiles.map(\.name).joined(separator: ", ")).
        Days must be Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday.
        Times must be 24-hour HH:mm. End earlier than start means overnight into the next day. Equal start/end is invalid. For all day use 00:00–24:00.
        Multiple entries per day are allowed. Pauses are optional, ISO-8601 dates with timezone, start inclusive/end exclusive; omit profile to pause all schedules. Weekly entries use the Mac's local timezone. Do not overlap entries. Do not include UUIDs, hardware keys, RPMs or extra fields.
        """
    }
    public static let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    public static func decode(_ text: String, profiles: [Profile]) throws -> (periods: [WeeklyPeriod], pauses: [SchedulePause]) {
        let root: [String: Any]
        do { root = try ImportValidation.root(Data(text.utf8)) }
        catch { throw ScheduleError("JSON: \(error.localizedDescription)") }
        guard Set(root.keys).isSubset(of: ["version", "entries", "pauses"]),
              let version = root["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              let entries = root["entries"] as? [[String: Any]], entries.count <= 1024 else { throw ScheduleError("Root: expected version 1 and an entries array (maximum 1024), with optional pauses.") }
        func profileID(_ name: Any?, path: String) throws -> String {
            guard let name = name as? String else { throw ScheduleError("\(path): expected a profile name.") }
            var matches = profiles.filter { $0.name == name }
            if matches.isEmpty, name == "School" {
                matches = profiles.filter { $0.id == "school" && $0.bundled }
            }
            guard matches.count == 1 else { throw ScheduleError("\(path): profile '\(name)' is unknown or ambiguous. Use an exact, unique profile name.") }; return matches[0].id
        }
        var periods: [WeeklyPeriod] = []
        for (index, entry) in entries.enumerated() {
            let path = "entries[\(index)]"
            guard Set(entry.keys) == ["profile", "day", "start", "end"], let day = entry["day"] as? String,
                  let weekday = days.firstIndex(of: day) else { throw ScheduleError("\(path): expected profile, day, start, end; day must be a full English weekday.") }
            func minute(_ field: String) throws -> Int {
                guard let value = entry[field] as? String else { throw ScheduleError("\(path).\(field): expected HH:mm.") }
                do { return try ScheduleEngine.parseTime(value, allowEndOfDay: field == "end") }
                catch { throw ScheduleError("\(path).\(field): \(error.localizedDescription)") }
            }
            let period = try WeeklyPeriod(profileID: profileID(entry["profile"], path: path + ".profile"), weekday: weekday + 1, startMinute: minute("start"), endMinute: minute("end"))
            do { try period.validate(profileIDs: Set(profiles.map(\.id))) } catch { throw ScheduleError("\(path): \(error.localizedDescription)") }
            periods.append(period)
        }
        guard root["pauses"] == nil || root["pauses"] is [[String: Any]] else { throw ScheduleError("pauses: expected an array.") }
        let formatter = ISO8601DateFormatter()
        let pauses = try (root["pauses"] as? [[String: Any]] ?? []).enumerated().map { index, entry in
            guard Set(entry.keys).isSubset(of: ["profile", "start", "end"]), let startText = entry["start"] as? String,
                  let endText = entry["end"] as? String, let start = formatter.date(from: startText), let end = formatter.date(from: endText), start < end else { throw ScheduleError("pauses[\(index)]: expected increasing ISO-8601 start/end with timezone.") }
            return try SchedulePause(profileID: entry["profile"].map { try profileID($0, path: "pauses[\(index)].profile") }, start: start, end: end)
        }
        guard pauses.count <= 256 else { throw ScheduleError("pauses: maximum 256 ranges.") }
        return (periods, pauses)
    }
}
