import Foundation

public struct ProfileApplication: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case bundle, process }
    public var id: String
    public var name: String
    public var kind: Kind
    public init(id: String, name: String, kind: Kind = .bundle) { self.id = id; self.name = name; self.kind = kind }
    public var matchingIdentifier: String { kind == .bundle ? id : "process:" + id }
    public func validate() throws {
        guard !id.isEmpty, !name.isEmpty, id.utf8.count <= 255, name.count <= 128,
              id.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              !id.contains("/"), kind != .process || (id != "." && id != "..") else {
            throw ScheduleError("Choose an application or a named running process.")
        }
    }
}

/// Portable user intent only. This never grants control authority or resumes a lease.
public struct ProfileActivationDefault: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case forever, duration, application }
    public var kind: Kind = .forever
    public var seconds: Int = 300
    public var applications: [ProfileApplication] = []
    // Legacy callers still edit the first entry; persisted rules use the complete group.
    public var applicationID: String {
        get { applications.first?.id ?? "" }
        set { if applications.isEmpty { applications = [.init(id: newValue, name: "")] } else { applications[0].id = newValue } }
    }
    public var applicationName: String {
        get { applications.first?.name ?? "" }
        set { if applications.isEmpty { applications = [.init(id: "", name: newValue)] } else { applications[0].name = newValue } }
    }
    public var applicationNames: String { applications.map(\.name).joined(separator: " or ") }
    public var applicationIdentifiers: Set<String> { Set(applications.map(\.matchingIdentifier)) }
    /// User automation only: runtime identity and fan authority are never stored.
    public var launchWhenOpened: Bool = false
    public init() {}
    private enum CodingKeys: String, CodingKey { case kind, seconds, applicationID, applicationName, applications, launchWhenOpened }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .forever
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 300
        if c.contains(.applications) { applications = try c.decode([ProfileApplication].self, forKey: .applications) }
        else {
            let id = try c.decodeIfPresent(String.self, forKey: .applicationID) ?? ""
            let name = try c.decodeIfPresent(String.self, forKey: .applicationName) ?? ""
            applications = id.isEmpty && name.isEmpty ? [] : [.init(id: id, name: name)]
        }
        launchWhenOpened = try c.decodeIfPresent(Bool.self, forKey: .launchWhenOpened) ?? false
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind); try c.encode(seconds, forKey: .seconds)
        try c.encode(applications, forKey: .applications); try c.encode(launchWhenOpened, forKey: .launchWhenOpened)
    }
    public func validate() throws {
        guard (1...2_678_400).contains(seconds), applications.count <= 32,
              applicationIdentifiers.count == applications.count,
              (kind != .application && !launchWhenOpened) || !applications.isEmpty else {
            throw ScheduleError("Choose a running application or a duration between one second and 31 days.")
        }
        try applications.forEach { try $0.validate() }
    }
}
public struct ShortcutBinding: Codable, Sendable, Equatable, Hashable {
    // Carbon virtual key code and portable modifier bits: command=1 option=2 control=4 shift=8.
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var key: String
    public init(keyCode: UInt32, modifiers: UInt32, key: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.key = key }
    public var label: String { (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 8 != 0 ? "⇧" : "") + (modifiers & 1 != 0 ? "⌘" : "") + key }
    public func validate() throws {
        guard keyCode < 128, modifiers < 16, modifiers & 7 != 0, !key.isEmpty, key.count <= 16, key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw ScheduleError("A shortcut must include Command, Option or Control and a supported key.") }
    }
}
