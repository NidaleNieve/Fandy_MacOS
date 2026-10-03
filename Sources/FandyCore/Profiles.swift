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
    public init(id: String = UUID().uuidString, name: String, kind: ProfileKind = .custom, bundled: Bool = false, curves: [FanCurve], floor: Double = 0, automaticAtIdle: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.bundled = bundled; defaultRevision = 1; self.curves = curves; self.floor = floor; self.automaticAtIdle = automaticAtIdle
    }
    public var protected: Bool { id == "system" || id == "max" }
    public var requiredSensors: Set<SensorRole> { requiredSensors(chipPolicy: .cpuGPU) }
    public func requiredSensors(chipPolicy: ChipControlPolicy) -> Set<SensorRole> {
        if kind == .system || kind == .maximum { return [] }
        return curves.filter(\.enabled).reduce(chipPolicy.required) { $0.union($1.input.required(chipPolicy: chipPolicy)) }
    }
    public func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 128, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
              floor.isFinite, (0...100).contains(floor), curves.count <= 4,
              Set(curves.map(\.input)).count == curves.count else { throw ControlError.invalidProfile("Invalid profile name, floor, or curve set.") }
        if protected {
            guard let original = BuiltInProfiles.all.first(where: { $0.id == id }), self == original else { throw ControlError.invalidProfile("System and Max are protected.") }
        } else { guard kind == .custom else { throw ControlError.invalidProfile("Only System and Max may use special modes.") } }
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
    public static let guardCurve = FanCurve(.chip, [(55,0),(65,15),(75,40),(80,70),(85,100)])
    public static let trackpad = FanCurve(.trackpad, [(27,20),(29,25),(31,40),(34,60),(38,85),(42,100)])
    public static let actuator = FanCurve(.actuator, [(25,20),(27,25),(29,40),(32,60),(36,85),(40,100)])
    public static let airflow = FanCurve(.airflow, [(33,20),(36,25),(40,40),(44,55),(50,75),(60,100)])
    public static let system = Profile(id: "system", name: "System", kind: .system, bundled: true, curves: [])
    public static let maximum = Profile(id: "max", name: "Max", kind: .maximum, bundled: true, curves: [])
    public static let systemPlus = Profile(id: "system-plus", name: "System+", bundled: true, curves: [chip], automaticAtIdle: true)
    public static let coolChassis = Profile(id: "cool-chassis", name: "Cool Chassis", bundled: true, curves: [chip, trackpad, actuator, airflow], floor: 20)
    public static let gaming: Profile = {
        var profile = Profile(id: "gaming", name: "Gaming", bundled: true, curves: [FanCurve(.chip, [(35,15),(45,25),(55,40),(65,55),(72,70),(77,85),(81,95),(85,100)])])
        profile.defaultRevision = 2; return profile
    }()
    public static let school: Profile = {
        var comfort = [trackpad, actuator, airflow]
        for i in comfort.indices { for j in comfort[i].points.indices { comfort[i].points[j].percent = max(0, comfort[i].points[j].percent / 2 - 10) } }
        return Profile(id: "school", name: "School", bundled: true, curves: [chip] + comfort, automaticAtIdle: true)
    }()
    public static let all = [system, maximum, systemPlus, coolChassis, gaming, school]
}
public struct Demand: Sendable, Equatable {
    public var percent: Double
    public var safetyPercent: Double
    public var byCurve: [CurveInput: Double]
}
public struct ProfileEngine: Sendable {
    public init() {}
    public func evaluate(_ profile: Profile, snapshot: HardwareSnapshot, now: Double, chipPolicy: ChipControlPolicy = .cpuGPU) throws -> Demand {
        try profile.validate()
        if profile.kind == .system { return Demand(percent: 0, safetyPercent: 0, byCurve: [:]) }
        try snapshot.validate(now: now, required: profile.requiredSensors(chipPolicy: chipPolicy))
        if profile.kind == .maximum { return Demand(percent: 100, safetyPercent: 0, byCurve: [:]) }
        let guardCurve = BuiltInProfiles.guardCurve
        let safety = try guardCurve.evaluate(guardCurve.temperature(in: snapshot, now: now, chipPolicy: chipPolicy))
        var byCurve: [CurveInput: Double] = [:]
        for curve in profile.curves where curve.enabled { byCurve[curve.input] = try curve.evaluate(curve.temperature(in: snapshot, now: now, chipPolicy: chipPolicy)) }
        return Demand(percent: profile.kind == .maximum ? 100 : max(profile.floor, byCurve.values.max() ?? 0, safety), safetyPercent: safety, byCurve: byCurve)
    }
}
