import Foundation
public enum ProfileKind: String, Codable, Sendable { case system, maximum, custom }
public struct Profile: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: ProfileKind
    public var bundled: Bool
    public var defaultRevision: Int
    public var curves: [FanCurve]
    public var floor: Double
    public var automaticAtIdle: Bool
    public var targetTemperature: TemperatureTarget?
    public var chipSources: Set<ChipSource>
    public var fanResponse: Double
    public var showInMenuBar = true
    public init(id: String = UUID().uuidString, name: String, kind: ProfileKind = .custom, bundled: Bool = false, curves: [FanCurve], floor: Double = 0, automaticAtIdle: Bool = false, targetTemperature: TemperatureTarget? = nil, chipSources: Set<ChipSource> = [.cpu, .gpu], fanResponse: Double? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.bundled = bundled; defaultRevision = 1; self.curves = curves; self.floor = floor; self.automaticAtIdle = automaticAtIdle; self.targetTemperature = targetTemperature
        self.chipSources = chipSources; self.fanResponse = fanResponse ?? (id == "school" ? 0 : 1)
    }
    private enum CodingKeys: String, CodingKey { case id, name, kind, bundled, defaultRevision, curves, floor, automaticAtIdle, targetTemperature, chipSources, fanResponse, showInMenuBar }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id); name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(ProfileKind.self, forKey: .kind); bundled = try values.decode(Bool.self, forKey: .bundled)
        defaultRevision = try values.decodeIfPresent(Int.self, forKey: .defaultRevision) ?? 1
        curves = try values.decode([FanCurve].self, forKey: .curves); floor = try values.decode(Double.self, forKey: .floor)
        automaticAtIdle = try values.decodeIfPresent(Bool.self, forKey: .automaticAtIdle) ?? false
        targetTemperature = try values.decodeIfPresent(TemperatureTarget.self, forKey: .targetTemperature)
        chipSources = try values.decodeIfPresent(Set<ChipSource>.self, forKey: .chipSources) ?? (curves.contains { $0.input == .chip && $0.enabled } || targetTemperature?.input == .chip ? [.cpu, .gpu] : [])
        // Special modes have no chip curve; retain their canonical protected representation.
        if kind != .custom && !values.contains(.chipSources) { chipSources = [.cpu, .gpu] }
        fanResponse = try values.decodeIfPresent(Double.self, forKey: .fanResponse) ?? (id == "school" ? 0 : 1)
        showInMenuBar = try values.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
    }
    public var exportFilename: String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
        let filename = String(String.UnicodeScalarView(name.unicodeScalars.map { forbidden.contains($0) ? UnicodeScalar(45)! : $0 })).trimmingCharacters(in: .whitespacesAndNewlines)
        return (filename.isEmpty ? "Profile" : filename) + ".json"
    }
    public var maximumConfiguredDemand: Double {
        if kind == .maximum { return 100 }
        return max(floor, curves.filter(\.enabled).flatMap(\.points).map(\.percent).max() ?? 0, targetTemperature == nil ? 0 : 100)
    }
    public var protected: Bool { id == "system" || id == "max" }
    public var requiredSensors: Set<SensorRole> { requiredSensors(chipPolicy: .cpuGPU) }
    public func requiredSensors(chipPolicy: ChipControlPolicy) -> Set<SensorRole> {
        if kind == .system || kind == .maximum { return [] }
        func required(_ input: CurveInput) -> Set<SensorRole> { input == .chip ? chipRoles(policy: chipPolicy) : input.required }
        return curves.filter(\.enabled).reduce(chipPolicy.required) { $0.union(required($1.input)) }.union(targetTemperature.map { required($0.input) } ?? [])
    }
    public func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 128, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
              floor.isFinite, (0...100).contains(floor), fanResponse.isFinite, (0...1).contains(fanResponse), curves.count <= 4,
              Set(curves.map(\.input)).count == curves.count else { throw ControlError.invalidProfile("Invalid profile name, floor, or curve set.") }
        if protected {
            var definition = self; definition.showInMenuBar = true
            guard let original = BuiltInProfiles.all.first(where: { $0.id == id }), definition == original else { throw ControlError.invalidProfile("System and Max are protected.") }
        } else { guard kind == .custom else { throw ControlError.invalidProfile("Only System and Max may use special modes.") } }
        try targetTemperature?.validate()
        if targetTemperature?.input == .chip || curves.contains(where: { $0.input == .chip && $0.enabled }) {
            guard !chipSources.isEmpty else { throw ControlError.invalidProfile("Select CPU or GPU for the chip curve or target.") }
        }
        try curves.forEach { try $0.validate() }
    }
    public func duplicated() -> Profile {
        var copy = self; copy.id = UUID().uuidString; copy.name = String(name.prefix(75)) + " Copy"; copy.bundled = false; copy.kind = .custom
        if kind == .system || kind == .maximum { copy.curves = BuiltInProfiles.systemPlus.curves; copy.floor = kind == .maximum ? 100 : 0 }
        return copy
    }
}
public struct Demand: Sendable, Equatable {
    public var percent: Double
    public var safetyPercent: Double
    public var byCurve: [CurveInput: Double]
    public var targetPercent: Double? = nil
    public var profilePercent: Double = 0
    public var winningInput: String {
        if let targetPercent, targetPercent == profilePercent { return "Temperature target" }
        if let input = byCurve.keys.sorted(by: { $0.rawValue < $1.rawValue }).first(where: { byCurve[$0] == profilePercent }) { return input.label + " curve" }
        return "Minimum airflow"
    }
}
public struct ProfileEngine: Sendable {
    public init() {}
    public func evaluate(_ profile: Profile, snapshot: HardwareSnapshot, now: Double, chipPolicy: ChipControlPolicy = .cpuGPU) throws -> Demand {
        try profile.validate()
        if profile.kind == .system { return Demand(percent: 0, safetyPercent: 0, byCurve: [:]) }
        try snapshot.validate(now: now, required: profile.requiredSensors(chipPolicy: chipPolicy))
        if profile.kind == .maximum { return Demand(percent: 100, safetyPercent: 0, byCurve: [:]) }
        var byCurve: [CurveInput: Double] = [:]
        for curve in profile.curves where curve.enabled { byCurve[curve.input] = try curve.evaluate(profile.temperature(for: curve.input, snapshot: snapshot, now: now, policy: chipPolicy)) }
        let target = try profile.targetTemperature.map { try $0.evaluate(profile.temperature(for: $0.input, snapshot: snapshot, now: now, policy: chipPolicy)) }
        let ordinary = max(profile.floor, byCurve.values.max() ?? 0, target ?? 0)
        return Demand(percent: ordinary, safetyPercent: 0, byCurve: byCurve, targetPercent: target, profilePercent: ordinary)
    }
}
