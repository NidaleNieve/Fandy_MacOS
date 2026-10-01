import Foundation
public struct ProfileArchive: Codable, Sendable {
    public var version: Int = 1
    public var profiles: [Profile]
    public var previousSelection: String?
    public init(profiles: [Profile], previousSelection: String? = nil) { self.profiles = profiles; self.previousSelection = previousSelection }
}
public struct ProfileLoadResult: Sendable {
    public var profiles: [Profile]
    public var issues: [String]
}
public struct ProfileStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() -> ProfileLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return ProfileLoadResult(profiles: BuiltInProfiles.all, issues: []) }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else { throw ControlError.malformedMessage }
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["version"] as? Int == 1,
                  let entries = object["profiles"] as? [[String: Any]], entries.count <= 128 else { throw ControlError.malformedMessage }
            var profiles: [Profile] = [], issues: [String] = [], ids = Set<String>()
            for entry in entries {
                do {
                    let bytes = try JSONSerialization.data(withJSONObject: entry)
                    var profile = try JSONDecoder().decode(Profile.self, from: bytes)
                    profile.bundled = BuiltInProfiles.all.contains { $0.id == profile.id }
                    try profile.validate()
                    guard ids.insert(profile.id).inserted else { throw ControlError.invalidProfile("Duplicate profile identifier.") }
                    profiles.append(profile)
                } catch { issues.append("A damaged profile was excluded: \(error.localizedDescription)") }
            }
            for original in BuiltInProfiles.all where !ids.contains(original.id) { profiles.append(original) }
            return ProfileLoadResult(profiles: profiles, issues: issues)
        } catch {
            return ProfileLoadResult(profiles: BuiltInProfiles.all, issues: ["Profile storage could not be decoded. Original file preserved; System selected."])
        }
    }
    public func save(_ profiles: [Profile], previousSelection: String?) throws {
        guard profiles.count <= 128, Set(profiles.map(\.id)).count == profiles.count,
              Set(BuiltInProfiles.all.map(\.id)).isSubset(of: Set(profiles.map(\.id))) else { throw ControlError.invalidProfile("Profile set must retain all built-ins.") }
        try profiles.forEach { try $0.validate() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(ProfileArchive(profiles: profiles, previousSelection: previousSelection))
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
