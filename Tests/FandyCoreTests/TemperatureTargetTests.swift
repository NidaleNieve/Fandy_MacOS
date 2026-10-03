import Foundation
import Testing
@testable import FandyCore

@Test func temperatureTargetsUseIndependentSmoothBands() throws {
    for input in CurveInput.allCases {
        let target = TemperatureTarget(input: input, celsius: TemperatureTarget.defaultTemperature(for: input))
        #expect(try target.evaluate(target.celsius) == 50)
        #expect(try target.evaluate(target.celsius - target.responseBand / 2) == 0)
        #expect(try target.evaluate(target.celsius + target.responseBand / 2) == 100)
        #expect(try target.evaluate(target.celsius + target.responseBand / 4) == 75)
        #expect(try target.evaluate(-100) == 0)
        #expect(try target.evaluate(200) == 100)
    }
}
@Test func temperatureTargetsRejectMalformedNumbers() {
    for value: Double in [.nan, .infinity, -.infinity, -1, 126] {
        #expect(throws: (any Error).self) { try TemperatureTarget(celsius: value).validate() }
    }
    #expect(throws: (any Error).self) { try TemperatureTarget().evaluate(.nan) }
    #expect(throws: (any Error).self) { try TemperatureTarget().evaluate(.infinity) }
}
@Test func targetDemandCannotSuppressCurvesFloorOrChipGuard() throws {
    var profile = Profile(name: "Goal", curves: [], targetTemperature: TemperatureTarget(input: .trackpad, celsius: 29))
    let demand = try ProfileEngine().evaluate(profile, snapshot: fixture(trackpad: 29), now: 10)
    #expect(demand.percent == 50 && demand.targetPercent == 50)
    profile.floor = 70
    #expect(try ProfileEngine().evaluate(profile, snapshot: fixture(trackpad: 29), now: 10).percent == 70)
    profile.curves = [FanCurve(.airflow, [(20,90),(60,100)])]
    #expect(try ProfileEngine().evaluate(profile, snapshot: fixture(trackpad: 29), now: 10).percent > 90)
    profile.curves = []; profile.floor = 0; profile.targetTemperature?.celsius = 125
    #expect(try ProfileEngine().evaluate(profile, snapshot: fixture(gpu: 85), now: 10).percent == 100)
}
@Test func targetRequiresCompleteQualifiedInputEvenWithoutCurves() throws {
    let profile = Profile(name: "Airflow goal", curves: [], targetTemperature: TemperatureTarget(input: .airflow, celsius: 36))
    #expect(profile.requiredSensors(chipPolicy: .conservativeEnvelope) == [.socPeak,.airflowLeft,.airflowTop,.airflowRight])
    var reading = fixture(); reading.sensors.removeAll { $0.role == .airflowRight }
    #expect(throws: (any Error).self) { try ProfileEngine().evaluate(profile, snapshot: reading, now: 10) }
    reading = fixture(); reading.sensors[reading.sensors.firstIndex { $0.role == .airflowTop }!].health = .unverified
    #expect(throws: (any Error).self) { try ProfileEngine().evaluate(profile, snapshot: reading, now: 10) }
    let preview = try ShadowProfileEngine.evaluate(profile, snapshot: reading, now: 10)
    #expect(preview.usesCandidates && preview.targetPercent != nil)
}
@Test func targetSensorFailureAndStalenessRestoreSystem() throws {
    let profile = Profile(name: "Surface goal", curves: [], targetTemperature: TemperatureTarget(input: .actuator, celsius: 27))
    for stale in [false, true] {
        var machine = ControlMachine(); _ = try machine.select(profile)
        var reading = fixture()
        let i = reading.sensors.firstIndex { $0.role == .actuator }!
        if stale { reading.sensors[i].sampledAt = 1 } else { reading.sensors[i].celsius = nil }
        guard case .restore = machine.step(reading, now: 10) else { Issue.record("Target failure did not request handback"); continue }
        #expect(machine.selected.id == "system" && machine.state == .restoringSystem)
    }
}
@Test func targetPersistenceAndInterchangeRemainBackwardCompatible() throws {
    var profile = BuiltInProfiles.school
    let old = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(Profile.self, from: old).targetTemperature == nil)
    profile.targetTemperature = .init(input: .trackpad, celsius: 28.5)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProfileStore(url: directory.appendingPathComponent("profiles.json"))
    let profiles = BuiltInProfiles.all.map { $0.id == profile.id ? profile : $0 }
    try store.save(profiles, previousSelection: "school")
    #expect(store.load().profiles.first { $0.id == "school" }?.targetTemperature == profile.targetTemperature)
    let imported = try ProfileInterchange.decode(ProfileInterchange.encode([profile]), existingCount: 6)
    #expect(imported.first?.targetTemperature == profile.targetTemperature)
    let scheduled = try ScheduledProfileInterchange.decode(ScheduledProfileInterchange.encode(profile, automation: .init()), existingCount: 6)
    #expect((scheduled.profiles + scheduled.replacements).first?.targetTemperature == profile.targetTemperature)
    let config = PortableConfiguration(profiles: profiles, automation: .init())
    #expect(try ConfigurationInterchange.decode(ConfigurationInterchange.encode(config)) == config)
}
@Test func targetImportRejectsHiddenAuthorityFields() throws {
    var profile = BuiltInProfiles.school.duplicated(); profile.targetTemperature = .init()
    var root = try #require(JSONSerialization.jsonObject(with: ProfileInterchange.encode([profile])) as? [String: Any])
    var entries = try #require(root["profiles"] as? [[String: Any]])
    entries[0]["targetTemperature"] = ["input":"chip","celsius":75,"qualification":true]
    root["profiles"] = entries
    #expect(throws: (any Error).self) { try ProfileInterchange.decode(JSONSerialization.data(withJSONObject: root), existingCount: 6) }
}
@Test func selectedNameMetadataCannotChangePolicyOrLeaseGeneration() throws {
    var machine = ControlMachine(); var profile = BuiltInProfiles.school
    _ = try machine.select(profile); let generation = machine.generation, state = machine.state
    profile.name = "Quiet Study"; try machine.updateSelectedName(from: profile)
    #expect(machine.selected.name == "Quiet Study" && machine.generation == generation && machine.state == state)
    profile.targetTemperature = .init()
    #expect(throws: (any Error).self) { try machine.updateSelectedName(from: profile) }
    #expect(machine.selected.targetTemperature == nil)
}
@Test func protectedProfilesCannotAcquireTemperatureTargets() {
    for var profile in [BuiltInProfiles.system, BuiltInProfiles.maximum] {
        profile.targetTemperature = .init()
        #expect(throws: (any Error).self) { try profile.validate() }
    }
}
