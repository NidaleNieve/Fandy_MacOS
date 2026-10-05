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
    public init(id: String = UUID().uuidString, name: String, kind: ProfileKind = .custom, bundled: Bool = false, curves: [FanCurve], floor: Double = 0, automaticAtIdle: Bool = false, targetTemperature: TemperatureTarget? = nil, chipSources: Set<ChipSource> = [.cpu, .gpu], fanResponse: Double? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.bundled = bundled; defaultRevision = 1; self.curves = curves; self.floor = floor; self.automaticAtIdle = automaticAtIdle; self.targetTemperature = targetTemperature
        self.chipSources = chipSources; self.fanResponse = fanResponse ?? (id == "school" ? 0 : 1)
    }
    private enum CodingKeys: String, CodingKey { case id, name, kind, bundled, defaultRevision, curves, floor, automaticAtIdle, targetTemperature, chipSources, fanResponse }
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
            guard let original = BuiltInProfiles.all.first(where: { $0.id == id }), self == original else { throw ControlError.invalidProfile("System and Max are protected.") }
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
public enum BuiltInProfiles {
    public static let chip = FanCurve(.chip, [(45,0),(55,10),(65,30),(75,55),(80,80),(85,100)])
    public static let trackpad = FanCurve(.trackpad, [(27,20),(29,25),(31,40),(34,60),(38,85),(42,100)])
    public static let actuator = FanCurve(.actuator, [(25,20),(27,25),(29,40),(32,60),(36,85),(40,100)])
    public static let airflow = FanCurve(.airflow, [(33,20),(36,25),(40,40),(44,55),(50,75),(60,100)])
    public static let system = Profile(id: "system", name: "System", kind: .system, bundled: true, curves: [])
    public static let maximum = Profile(id: "max", name: "Max", kind: .maximum, bundled: true, curves: [])
    public static let systemPlus = Profile(id: "system-plus", name: "System+", bundled: true, curves: [chip], automaticAtIdle: true, fanResponse: 0.2)
    public static let coolChassis: Profile = {
        var profile = Profile(id: "cool-chassis", name: "Cool Chassis", bundled: true, curves: [
            chip,
            FanCurve(.trackpad, [(26,0),(29,25),(31,40),(34,60),(38,85),(42,100)]),
            FanCurve(.actuator, [(25,0),(27.1,22),(29,40),(32,60),(36,85),(40,100)]),
            FanCurve(.airflow, [(32,0),(35.5,18),(40,40),(44,55),(50,75),(60,100)])
        ], floor: 0, fanResponse: 0.2)
        profile.defaultRevision = 3; return profile
    }()
    /// Upgrade only exact old factory shapes; edited curves/floors stay intact.
    public static func upgradeCoolChassisDefault(_ profile: Profile) -> Profile {
        guard profile.id == "cool-chassis", profile.name == "Cool Chassis", profile.kind == .custom,
              profile.defaultRevision < 3, !profile.automaticAtIdle, profile.targetTemperature == nil,
              profile.curves.count == 4, profile.curves.allSatisfy(\.enabled) else { return profile }
        let original = [chip, trackpad, actuator, airflow]
        let previous = [chip,
            FanCurve(.trackpad, [(26,0),(29,25),(31,40),(34,60),(38,85),(42,100)]),
            FanCurve(.actuator, [(24.9,0),(27.1,20),(29,40),(32,60),(36,85),(40,100)]),
            FanCurve(.airflow, [(31.4,0),(36,20),(40,40),(44,55),(50,75),(60,100)])]
        func matches(_ curves: [FanCurve]) -> Bool {
            zip(profile.curves, curves).allSatisfy { stored, factory in
                stored.input == factory.input && stored.points.map { [$0.temperature, $0.percent] } == factory.points.map { [$0.temperature, $0.percent] }
            }
        }
        if (profile.defaultRevision == 1 && profile.floor == 20 && matches(original)) ||
            (profile.defaultRevision == 2 && profile.floor == 0 && matches(previous)) {
            var updated = coolChassis; updated.fanResponse = profile.fanResponse; updated.chipSources = profile.chipSources; return updated
        }
        return profile
    }
    public static let gaming: Profile = {
        var profile = Profile(id: "gaming", name: "Gaming", bundled: true, curves: [FanCurve(.chip, [(35,15),(45,25),(55,40),(65,55),(72,70),(77,85),(81,95),(85,100)])])
        profile.defaultRevision = 2; return profile
    }()
    public static let school: Profile = {
        var comfort = [trackpad, actuator, airflow]
        for i in comfort.indices { for j in comfort[i].points.indices { comfort[i].points[j].percent = max(0, comfort[i].points[j].percent / 2 - 10) } }
        let quietChip = FanCurve(.chip, [(45,0),(57.8,9),(70.3,15),(77.2,33),(82.6,47),(86.9,52)])
        var profile = Profile(id: "school", name: "Silent", bundled: true, curves: [quietChip] + comfort, automaticAtIdle: true)
        profile.defaultRevision = 3; return profile
    }()
    /// Migrate only the unchanged factory definition, never a user's tuning.
    public static func upgradeSchoolDefault(_ profile: Profile) -> Profile {
        var oldCurves = school.curves
        switch profile.defaultRevision {
        case 1: oldCurves[0] = chip
        case 2: oldCurves[0] = FanCurve(.chip, [(45,0),(56.9,14),(66.1,35),(73.8,47),(79.3,50),(86.9,52)])
        default: return profile
        }
        guard profile.id == "school", ["School", "Silent"].contains(profile.name), profile.defaultRevision < 3,
              profile.kind == .custom, profile.floor == 0, profile.automaticAtIdle,
              profile.targetTemperature == nil, profile.curves.count == oldCurves.count,
              zip(profile.curves, oldCurves).allSatisfy({ stored, original in
                  stored.enabled == original.enabled && stored.input == original.input &&
                  stored.points.map { [$0.temperature, $0.percent] } == original.points.map { [$0.temperature, $0.percent] }
              }) else { return profile }
        var updated = profile; updated.curves[0] = school.curves[0]; updated.defaultRevision = 3
        return updated
    }
    /// Keep stable IDs and all user tuning; only the legacy built-in label changes.
    public static func normalizeName(_ profile: Profile) -> Profile {
        guard profile.id == "school", profile.bundled, profile.name == "School" else { return profile }
        var updated = profile; updated.name = "Silent"; return updated
    }
    public static let all = [system, maximum, systemPlus, coolChassis, gaming, school]
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
