import Foundation
import Testing
@testable import FandyCore

@Test func menuVisibilityDefaultsAndPortableProfiles() throws {
    #expect(try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8)).showActivationTiming)
    for original in BuiltInProfiles.all {
        #expect(original.showInMenuBar)
        var hidden = original; hidden.showInMenuBar = false
        try hidden.validate()
        let imported = try ScheduledProfileInterchange.decode(ScheduledProfileInterchange.encode(hidden, automation: .init()), existingCount: 6)
        #expect(imported.profiles.first?.showInMenuBar == false || imported.replacements.first?.showInMenuBar == false)
        #expect(!hidden.duplicated().showInMenuBar)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "showInMenuBar")
        #expect(try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: object)).showInMenuBar)
    }
    var config = AutomationConfiguration(); config.preferences.showActivationTiming = false
    let archive = try ConfigurationInterchange.decode(ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: config)))
    #expect(!archive.automation.preferences.showActivationTiming)
}

@Test func hiddenProtectedProfilesStillRejectCoolingChanges() throws {
    for original in [BuiltInProfiles.system, BuiltInProfiles.maximum] {
        var hidden = original; hidden.showInMenuBar = false; try hidden.validate()
        hidden.floor = 1
        #expect(throws: ControlError.self) { try hidden.validate() }
        hidden = original; hidden.showInMenuBar = false; hidden.name = "Changed"
        #expect(throws: ControlError.self) { try hidden.validate() }
    }
}

@Test func factoryUpgradePreservesMenuVisibility() {
    var old = BuiltInProfiles.coolChassis
    old.defaultRevision = 1; old.floor = 20
    old.curves = [BuiltInProfiles.chip, BuiltInProfiles.trackpad, BuiltInProfiles.actuator, BuiltInProfiles.airflow]
    old.showInMenuBar = false
    let upgraded = BuiltInProfiles.upgradeCoolChassisDefault(old)
    #expect(upgraded.defaultRevision == 3 && !upgraded.showInMenuBar)
}

@Test func presentationVisibilityDoesNotRestartController() throws {
    var machine = ControlMachine()
    _ = try machine.select(BuiltInProfiles.coolChassis)
    let generation = machine.generation, state = machine.state
    var hidden = machine.selected; hidden.showInMenuBar = false
    try machine.updateSelectedName(from: hidden)
    #expect(!machine.selected.showInMenuBar && machine.generation == generation && machine.state == state)
}
