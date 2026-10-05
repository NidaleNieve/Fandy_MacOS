import Foundation
import Testing
@testable import FandyCore

@Test func silentBuiltinKeepsIdentityAndExportsItsVisibleName() {
    #expect(BuiltInProfiles.school.id == "school")
    #expect(BuiltInProfiles.school.name == "Silent")
    #expect(BuiltInProfiles.school.exportFilename == "Silent.json")
}
@Test func silentMigrationPreservesEditedCoolingAndAllAutomation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProfileStore(url: directory.appendingPathComponent("profiles.json"))
    var legacy = BuiltInProfiles.school; legacy.name = "School"; legacy.floor = 17
    legacy.fanResponse = 0.25; legacy.curves[0].points[1].percent = 7
    var automation = AutomationConfiguration()
    automation.periods = [.init(profileID: "school", weekday: 1, startMinute: 510, endMinute: 750)]
    automation.preferences.defaultProfileID = "school"
    automation.activationDefaults["school"] = .init()
    automation.activationDefaults["school"]?.kind = .duration
    automation.activationDefaults["school"]?.seconds = 300
    try JSONEncoder().encode(ProfileArchive(profiles: [legacy], previousSelection: "school", automation: automation)).write(to: store.url)
    let loaded = store.load(); var expected = legacy; expected.name = "Silent"
    #expect(loaded.profiles.first { $0.id == "school" } == expected)
    #expect(loaded.automation == automation)
    try store.save(loaded.profiles, previousSelection: "school", automation: loaded.automation)
    #expect(store.load().profiles.first { $0.id == "school" } == expected)
    var renamed = legacy; renamed.name = "Study"; try store.save(BuiltInProfiles.all.map { $0.id == "school" ? renamed : $0 }, previousSelection: nil)
    #expect(store.load().profiles.first { $0.id == "school" }?.name == "Study")
}
@Test func silentLegacyConfigurationAndScheduledProfileImportsPreserveRules() throws {
    var legacy = BuiltInProfiles.school; legacy.name = "School"; legacy.floor = 13
    var automation = AutomationConfiguration()
    automation.periods = [.init(profileID: "school", weekday: 2, startMinute: 600, endMinute: 720)]
    let profiles = BuiltInProfiles.all.map { $0.id == "school" ? legacy : $0 }
    let config = try ConfigurationInterchange.decode(ConfigurationInterchange.encode(.init(profiles: profiles, automation: automation)))
    #expect(config.profiles.first { $0.id == "school" }?.name == "Silent")
    #expect(config.automation == automation)
    let scheduled = try ScheduledProfileInterchange.decode(ScheduledProfileInterchange.encode(legacy, automation: automation), existingCount: 6)
    #expect(scheduled.replacements.first?.name == "Silent")
    #expect(scheduled.replacements.first?.floor == 13)
    #expect(scheduled.periods.map { [$0.profileID, String($0.weekday), String($0.startMinute), String($0.endMinute), String($0.enabled)] } == automation.periods.map { [$0.profileID, String($0.weekday), String($0.startMinute), String($0.endMinute), String($0.enabled)] })
    var custom = legacy.duplicated(); custom.name = "School"
    let customConfig = try ConfigurationInterchange.decode(ConfigurationInterchange.encode(.init(profiles: profiles + [custom], automation: automation)))
    #expect(customConfig.profiles.first { $0.id == custom.id }?.name == "School")
}
@Test func silentTextSchedulesAcceptLegacyAliasButPreferAnExactName() throws {
    var silent = BuiltInProfiles.school; silent.name = "Silent"
    let text = #"{"version":1,"entries":[{"profile":"School","day":"Monday","start":"08:30","end":"12:30"}]}"#
    #expect(try ScheduleTextImport.decode(text, profiles: [silent]).periods.first?.profileID == "school")
    var custom = silent.duplicated(); custom.name = "School"
    #expect(try ScheduleTextImport.decode(text, profiles: [silent, custom]).periods.first?.profileID == custom.id)
    #expect(!ScheduleTextImport.prompt(profiles: [silent]).contains("\"profile\":\"School\""))
}
