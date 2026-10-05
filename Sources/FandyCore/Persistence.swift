import Foundation
public struct ProfileArchive: Codable, Sendable {
    public var version: Int = 2
    public var profiles: [Profile]
    public var previousSelection: String?
    public var automation: AutomationConfiguration
    private enum CodingKeys: String, CodingKey { case version, profiles, previousSelection, automation }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        profiles = try c.decode([Profile].self, forKey: .profiles)
        previousSelection = try c.decodeIfPresent(String.self, forKey: .previousSelection)
        automation = try c.decodeIfPresent(AutomationConfiguration.self, forKey: .automation) ?? .init()
    }
    public init(profiles: [Profile], previousSelection: String? = nil, automation: AutomationConfiguration = .init()) { self.profiles = profiles; self.previousSelection = previousSelection; self.automation = automation }
}
public struct ProfileLoadResult: Sendable {
    public var profiles: [Profile]
    public var issues: [String]
    public var automation: AutomationConfiguration = .init()
}
public struct ProfileStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() -> ProfileLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return ProfileLoadResult(profiles: BuiltInProfiles.all, issues: []) }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else { throw ControlError.malformedMessage }
            let data = try Self.readBounded(url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], [1, 2].contains(object["version"] as? Int ?? 0),
                  let entries = object["profiles"] as? [[String: Any]], entries.count <= 128 else { throw ControlError.malformedMessage }
            var profiles: [Profile] = [], issues: [String] = [], ids = Set<String>()
            for entry in entries {
                do {
                    let bytes = try JSONSerialization.data(withJSONObject: entry)
                    var profile = try JSONDecoder().decode(Profile.self, from: bytes)
                    profile.bundled = BuiltInProfiles.all.contains { $0.id == profile.id }
                    if profile.id == "gaming", profile.defaultRevision == 1,
                       profile.floor == 0, !profile.automaticAtIdle, profile.curves.count == 1,
                       profile.curves[0].enabled, profile.curves[0].input == .chip,
                       profile.curves[0].points.map({ [$0.temperature, $0.percent] }) == [[55,0],[65,25],[72,45],[77,65],[81,85],[85,100]] {
                        profile.curves = BuiltInProfiles.gaming.curves; profile.defaultRevision = 2
                    }
                    profile = BuiltInProfiles.upgradeCoolChassisDefault(profile)
                    profile = BuiltInProfiles.upgradeSchoolDefault(profile)
                    try profile.validate()
                    guard ids.insert(profile.id).inserted else { throw ControlError.invalidProfile("Duplicate profile identifier.") }
                    profiles.append(profile)
                } catch { issues.append("A damaged profile was excluded: \(error.localizedDescription)") }
            }
            for original in BuiltInProfiles.all where !ids.contains(original.id) { profiles.append(original) }
            if profiles.count > 128 {
                for index in profiles.indices.reversed() where profiles.count > 128 && !profiles[index].bundled {
                    profiles.remove(at: index)
                }
                issues.append("Excess custom profiles were excluded to preserve built-ins and the storage limit.")
            }
            var automation = AutomationConfiguration()
            if let stored = object["automation"] {
                do {
                    automation = try JSONDecoder().decode(AutomationConfiguration.self, from: JSONSerialization.data(withJSONObject: stored))
                    try automation.validate(profileIDs: Set(profiles.map(\.id)))
                } catch { automation = .init(); issues.append("Damaged automation settings excluded; schedules disabled.") }
            }
            return ProfileLoadResult(profiles: profiles, issues: issues, automation: automation)
        } catch {
            return ProfileLoadResult(profiles: BuiltInProfiles.all, issues: ["Profile storage could not be decoded. Original file preserved; System selected."])
        }
    }
    public func save(_ profiles: [Profile], previousSelection: String?, automation: AutomationConfiguration = .init()) throws {
        guard profiles.count <= 128, Set(profiles.map(\.id)).count == profiles.count,
              Set(BuiltInProfiles.all.map(\.id)).isSubset(of: Set(profiles.map(\.id))) else { throw ControlError.invalidProfile("Profile set must retain all built-ins.") }
        try profiles.forEach { try $0.validate() }
        try automation.validate(profileIDs: Set(profiles.map(\.id)))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(ProfileArchive(profiles: profiles, previousSelection: previousSelection, automation: automation))
        guard bytes.count <= 1_048_576 else { throw ControlError.malformedMessage }
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let result = load()
            let suffix = result.issues.isEmpty ? "backup" : "corrupt-\(Int(Date().timeIntervalSince1970))"
            let preservation = url.appendingPathExtension(suffix)
            if fm.fileExists(atPath: preservation.path) { try fm.removeItem(at: preservation) }
            try fm.copyItem(at: url, to: preservation)
        }
        try bytes.write(to: url, options: .atomic)
    }
}

public extension ProfileStore {
    static func readBounded(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= 1_048_576 {
            let chunk = try handle.read(upToCount: min(65_536, 1_048_577 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw ControlError.malformedMessage
    }
}

/// Serial disk writes; older revisions cannot overwrite newer requests.
public actor ProfilePersistence {
    private let write: @Sendable (ProfileArchive) throws -> Void
    private var newest: UInt64 = 0
    private var acknowledged: PortableConfiguration?
    public init(store: ProfileStore) {
        write = { try store.save($0.profiles, previousSelection: $0.previousSelection, automation: $0.automation) }
    }
    /// A synchronous adapter preserves serial writes and permits deterministic failure tests.
    init(write: @escaping @Sendable (ProfileArchive) throws -> Void) { self.write = write }
    public func save(_ profiles: [Profile], selection: String?, revision: UInt64, automation: AutomationConfiguration = .init()) throws {
        guard revision >= newest else { return }
        newest = revision
        let configuration = PortableConfiguration(profiles: profiles, automation: automation)
        // Previous selection is legacy metadata, never persisted activation authority.
        guard configuration != acknowledged else { return }
        do { try write(ProfileArchive(profiles: profiles, previousSelection: selection, automation: automation)) }
        catch { acknowledged = nil; throw error }
        acknowledged = configuration
    }
}

/// Interchange carries only validated custom profile definitions, never control authority.
public enum ProfileInterchange {
    private struct Archive: Codable { let version: Int; let profiles: [Profile] }
    public static func encode(_ profiles: [Profile]) throws -> Data {
        guard !profiles.isEmpty, profiles.count <= 128 else { throw ControlError.malformedMessage }
        let customs = profiles.map { profile -> Profile in
            var copy = profile.duplicated(); copy.name = profile.name; return copy
        }
        try customs.forEach { try $0.validate() }
        let data = try JSONEncoder().encode(Archive(version: 1, profiles: customs))
        guard data.count <= 1_048_576 else { throw ControlError.malformedMessage }
        return data
    }
    public static func decode(_ data: Data, existingCount: Int) throws -> [Profile] {
        let root: [String: Any]
        do {
            root = try ImportValidation.root(data)
            try ImportValidation.profiles(root["profiles"])
        } catch { throw ControlError.malformedMessage }
        guard Set(root.keys) == ["version", "profiles"] else { throw ControlError.malformedMessage }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 1, !archive.profiles.isEmpty, existingCount >= 0,
              archive.profiles.count <= 128, archive.profiles.count <= 128 - min(existingCount, 128),
              Set(archive.profiles.map(\.id)).count == archive.profiles.count else { throw ControlError.malformedMessage }
        return try archive.profiles.map { profile in
            guard !profile.protected, !profile.bundled, profile.kind == .custom,
                  !BuiltInProfiles.all.contains(where: { $0.id == profile.id }) else { throw ControlError.malformedMessage }
            try profile.validate()
            var copy = profile.duplicated(); copy.name = profile.name
            return copy
        }
    }
}
