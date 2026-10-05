import Foundation
import Testing
@testable import FandyCore

@Test func fanPercentageRoundTripsCurveLevelsIndependently() throws {
    for fan in [Fan(id: 0, min: 2317, max: 7826, actual: 2400), Fan(id: 1, min: 1800, max: 6800, actual: 2000)] {
        for percent in [0.0, 28, 50, 100] {
            #expect(abs(try fan.percent(rpm: fan.rpm(percent: percent)) - percent) < 0.000001)
        }
        #expect(try fan.percent(rpm: 0) == 0)
        #expect(try fan.percent(rpm: fan.minimumRPM / 2) == 0)
        #expect(try fan.percent(rpm: fan.maximumRPM * 1.1) == 100)
        for invalid in [Double.nan, .infinity, -1] {
            #expect(throws: ControlError.self) { try fan.percent(rpm: invalid) }
        }
    }
    #expect(throws: ControlError.self) { try Fan(id: 0, min: 3000, max: 3000, actual: 3000).percent(rpm: 3000) }
}

@Test func minimumFloorProducesRequestedLevelWithoutAddingMinimumTwice() throws {
    for floor in [28.0, 50] {
        var profile = BuiltInProfiles.school; profile.floor = floor
        var machine = ControlMachine(); _ = try machine.select(profile)
        var lastTargets: [FanTarget] = []
        for time in 1...15 {
            let effect = machine.step(fixture(at: Double(time), cpu: 40, gpu: 40), now: Double(time))
            if case let .apply(targets, generation, _, _) = effect {
                lastTargets = targets; machine.applied(generation: generation)
            }
        }
        #expect(machine.state == .customActive && abs(machine.percent - floor) < 0.000001)
        #expect(lastTargets.count == 2)
        for (fan, target) in zip(fixture().fans, lastTargets) {
            #expect(abs(try fan.percent(rpm: target.rpm) - floor) < 0.000001)
        }
    }
}

@Test func quietSchoolMatchesRequestedCurveAndRetainsChipSafety() throws {
    let school = BuiltInProfiles.school
    #expect(school.defaultRevision == 3 && school.floor == 0 && school.automaticAtIdle)
    #expect(school.curves[0].points.map { [$0.temperature, $0.percent] } == [[45,0],[57.8,9],[70.3,15],[77.2,33],[82.6,47],[86.9,52]])
    #expect(school.curves[1].points.map { [$0.temperature, $0.percent] } == [[27,0],[29,2.5],[31,10],[34,20],[38,32.5],[42,40]])
    #expect(school.curves[2].points.map { [$0.temperature, $0.percent] } == [[25,0],[27,2.5],[29,10],[32,20],[36,32.5],[40,40]])
    #expect(school.curves[3].points.map { [$0.temperature, $0.percent] } == [[33,0],[36,2.5],[40,10],[44,17.5],[50,27.5],[60,40]])
    #expect(try ProfileEngine().evaluate(school, snapshot: fixture(cpu: 40, gpu: 40), now: 10).percent == 0)
    #expect(try ProfileEngine().evaluate(school, snapshot: fixture(gpu: 85), now: 10).percent == 100)
    #expect(try ProfileEngine().evaluate(school, snapshot: fixture(cpu: 80), now: 10).percent == 70)
}

@Test func schoolFactoryMigrationPreservesCustomizationsAndAutomation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ProfileStore(url: directory.appendingPathComponent("profiles.json"))
    var old = BuiltInProfiles.school; old.curves[0] = BuiltInProfiles.chip; old.defaultRevision = 1
    var automation = AutomationConfiguration()
    automation.periods = [.init(profileID: "school", weekday: 1, startMinute: 600, endMinute: 660)]
    try JSONEncoder().encode(ProfileArchive(profiles: [old], automation: automation)).write(to: store.url)
    let loaded = store.load()
    #expect(loaded.profiles.first { $0.id == "school" }?.curves == BuiltInProfiles.school.curves)
    #expect(loaded.automation == automation)
    for customization in 0...3 {
        var edited = old
        switch customization {
        case 0: edited.floor = 28
        case 1: edited.curves[0].points[1].percent = 11
        case 2: edited.curves[1].enabled = false
        default: edited.name = "Quiet Study"
        }
        try JSONEncoder().encode(ProfileArchive(profiles: [edited])).write(to: store.url)
        #expect(store.load().profiles.first { $0.id == "school" } == edited)
    }
}

@Test func previousQuietSchoolMigratesOnlyUneditedFactoryCurve() {
    var old = BuiltInProfiles.school; old.defaultRevision = 2
    old.curves[0] = FanCurve(.chip, [(45,0),(56.9,14),(66.1,35),(73.8,47),(79.3,50),(86.9,52)])
    #expect(BuiltInProfiles.upgradeSchoolDefault(old).curves == BuiltInProfiles.school.curves)
    old.curves[0].points[2].percent = 34
    #expect(BuiltInProfiles.upgradeSchoolDefault(old) == old)
}
