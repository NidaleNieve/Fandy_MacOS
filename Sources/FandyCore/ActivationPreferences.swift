import Foundation

/// Portable user intent only. This never grants control authority or resumes a lease.
public struct ProfileActivationDefault: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case forever, duration, application }
    public var kind: Kind = .forever
    public var seconds: Int = 300
    public var applicationID: String = ""
    public var applicationName: String = ""
    public init() {}
    public func validate() throws {
        guard (1...2_678_400).contains(seconds), applicationID.utf8.count <= 255, applicationName.count <= 128,
              kind != .application || (!applicationID.isEmpty && !applicationName.isEmpty) else {
            throw ScheduleError("Choose a running application or a duration between one second and 31 days.")
        }
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
