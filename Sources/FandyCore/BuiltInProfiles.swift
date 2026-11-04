import Foundation

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
        if (profile.defaultRevision == 1 && profile.floor == 20 && matches(profile, curves: original)) ||
            (profile.defaultRevision == 2 && profile.floor == 0 && matches(profile, curves: previous)) {
            var updated = coolChassis; updated.fanResponse = profile.fanResponse; updated.chipSources = profile.chipSources; updated.showInMenuBar = profile.showInMenuBar; return updated
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
              profile.targetTemperature == nil, matches(profile, curves: oldCurves) else { return profile }
        var updated = profile; updated.curves[0] = school.curves[0]; updated.defaultRevision = 3
        return updated
    }
    /// Keep stable IDs and all user tuning; only the legacy built-in label changes.
    public static func normalizeName(_ profile: Profile) -> Profile {
        guard profile.id == "school", profile.bundled, profile.name == "School" else { return profile }
        var updated = profile; updated.name = "Silent"; return updated
    }
    /// Only persistence runs factory upgrades. Imports keep their supplied tuning.
    static func migrateStoredDefinition(_ profile: Profile) -> Profile {
        normalizeName(upgradeSchoolDefault(upgradeCoolChassisDefault(upgradeGamingDefault(profile))))
    }
    private static func upgradeGamingDefault(_ profile: Profile) -> Profile {
        guard profile.id == "gaming", profile.defaultRevision == 1, profile.floor == 0,
              !profile.automaticAtIdle,
              matches(profile, curves: [FanCurve(.chip, [(55,0),(65,25),(72,45),(77,65),(81,85),(85,100)])]) else { return profile }
        var updated = profile
        updated.curves = gaming.curves; updated.defaultRevision = 2
        return updated
    }
    /// Factory matching deliberately ignores point UUIDs.
    private static func matches(_ profile: Profile, curves: [FanCurve]) -> Bool {
        profile.curves.count == curves.count && zip(profile.curves, curves).allSatisfy { stored, factory in
            stored.enabled == factory.enabled && stored.input == factory.input &&
                stored.points.map { [$0.temperature, $0.percent] } == factory.points.map { [$0.temperature, $0.percent] }
        }
    }
    public static let all = [system, maximum, systemPlus, coolChassis, gaming, school]
}
