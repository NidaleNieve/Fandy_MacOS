import Foundation
import Testing
@testable import FandyCore

@Test func activationPreferencesDefaultAndPortableRoundTrip() throws {
    let migrated = try JSONDecoder().decode(AutomationConfiguration.self, from: Data("{}".utf8))
    #expect(migrated.activationDefaults.isEmpty && migrated.preferences.shortcuts.isEmpty)
    var config = AutomationConfiguration(), rule = ProfileActivationDefault()
    rule.kind = .duration; rule.seconds = 300; config.activationDefaults["max"] = rule
    config.preferences.shortcuts["menu"] = ShortcutBinding(keyCode: 3, modifiers: 5, key: "F")
    let portable = PortableConfiguration(profiles: BuiltInProfiles.all, automation: config)
    #expect(try ConfigurationInterchange.decode(ConfigurationInterchange.encode(portable)) == portable)
    let profile = try ScheduledProfileInterchange.decode(ScheduledProfileInterchange.encode(BuiltInProfiles.maximum, automation: config), existingCount: 6)
    #expect(profile.activationDefaults["max"] == rule)
}
@Test func shortcutConflictsAndInvalidActivationDefaultsAreRejected() throws {
    let ids = Set(BuiltInProfiles.all.map(\.id)); var config = AutomationConfiguration()
    let binding = ShortcutBinding(keyCode: 3, modifiers: 5, key: "F")
    config.preferences.shortcuts = ["menu":binding, "max":binding]
    #expect(throws: (any Error).self) { try config.validate(profileIDs: ids) }
    config.preferences.shortcuts = ["max": ShortcutBinding(keyCode: 3, modifiers: 8, key: "F")]
    #expect(throws: (any Error).self) { try config.validate(profileIDs: ids) }
    config.preferences.shortcuts = [:]; var rule = ProfileActivationDefault(); rule.kind = .application
    config.activationDefaults["gaming"] = rule
    #expect(throws: (any Error).self) { try config.validate(profileIDs: ids) }
    rule.kind = .duration; rule.seconds = -1; config.activationDefaults["max"] = rule
    #expect(throws: (any Error).self) { try config.validate(profileIDs: ids) }
}
@Test func individualCustomActivationDefaultsAreRemappedWithoutAuthority() throws {
    var custom = BuiltInProfiles.gaming.duplicated(); custom.name = "Custom"
    var rule = ProfileActivationDefault(); rule.kind = .application; rule.applicationID = "example.game"; rule.applicationName = "Game"
    var config = AutomationConfiguration(); config.activationDefaults[custom.id] = rule
    let imported = try ScheduledProfileInterchange.decode(ScheduledProfileInterchange.encode(custom, automation: config), existingCount: 6)
    let copy = try #require(imported.profiles.first)
    #expect(copy.id != custom.id && imported.activationDefaults[copy.id] == rule)
    var object = try #require(JSONSerialization.jsonObject(with: ScheduledProfileInterchange.encode(custom, automation: config)) as? [String: Any])
    object["activationDefaults"] = [custom.id:["kind":"duration", "seconds":300, "manualRPM":8000]]
    #expect(throws: (any Error).self) { try ScheduledProfileInterchange.decode(JSONSerialization.data(withJSONObject: object), existingCount: 6) }
}
@Test func cancellationScheduleLookaheadHonorsLimitsPausesAndOvernight() throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
    var config = AutomationConfiguration(); config.periods = [WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 11*60, endMinute: 12*60)]
    #expect(!ScheduleEngine.hasActivity(in: config, after: date, before: date.addingTimeInterval(300), calendar: calendar))
    #expect(ScheduleEngine.hasActivity(in: config, after: date, before: date.addingTimeInterval(7200), calendar: calendar))
    config.pauses = [SchedulePause(start: date, end: date.addingTimeInterval(86400))]
    #expect(!ScheduleEngine.hasActivity(in: config, after: date, before: date.addingTimeInterval(7200), calendar: calendar))
    config.pauses = []; config.periods = [WeeklyPeriod(profileID: "gaming", weekday: 7, startMinute: 23*60, endMinute: 90)]
    let monday = calendar.startOfDay(for: date)
    #expect(ScheduleEngine.hasActivity(in: config, after: monday, before: monday.addingTimeInterval(3600), calendar: calendar))
}
@Test func gamingDefaultIsEarlierAndMoreAggressiveWithoutChangingCustomCurves() throws {
    let gaming = try #require(BuiltInProfiles.gaming.curves.first), regular = BuiltInProfiles.chip
    for temperature in stride(from: 35.0, through: 85, by: 1) { #expect(try gaming.evaluate(temperature) >= regular.evaluate(temperature)) }
    #expect(try gaming.evaluate(40) > 0); #expect(try gaming.evaluate(80) >= 90)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ProfileStore(url: dir.appendingPathComponent("profiles.json"))
    var old = BuiltInProfiles.gaming; old.defaultRevision = 1; old.curves = [FanCurve(.chip, [(55,0),(65,25),(72,45),(77,65),(81,85),(85,100)])]
    try store.save(BuiltInProfiles.all.map { $0.id == "gaming" ? old : $0 }, previousSelection: nil)
    #expect(store.load().profiles.first { $0.id == "gaming" }?.defaultRevision == 2)
    old.curves[0].points[0].percent = 5
    try store.save(BuiltInProfiles.all.map { $0.id == "gaming" ? old : $0 }, previousSelection: nil)
    #expect(store.load().profiles.first { $0.id == "gaming" }?.curves == old.curves)
}

@Test func verifiedRestorationRetryClearsUnverifiedFaultButPreservesOtherFailureContext() {
    var machine = ControlMachine()
    _ = machine.fail(ControlError.restorationUnverified)
    machine.restored(generation: machine.generation, verified: false)
    #expect(machine.state == .fault && machine.fault != nil)
    machine.restored(generation: machine.generation, verified: true)
    #expect(machine.state == .system && machine.fault == nil)
    _ = machine.fail(ControlError.sensorUnavailable(.gpuPeak))
    machine.restored(generation: machine.generation, verified: true)
    #expect(machine.state == .system && machine.fault != nil)
}
