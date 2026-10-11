import Foundation
import Testing
@testable import FandyCore

@Test func temporarySpeedVisibilityDefaultsOnAndSurvivesPortableConfiguration() throws {
    #expect(AppPreferences().showCustomFanSpeed)
    #expect(try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8)).showCustomFanSpeed)
    var automation = AutomationConfiguration()
    automation.preferences.showCustomFanSpeed = false
    let configuration = PortableConfiguration(profiles: BuiltInProfiles.all, automation: automation)
    let bytes = try ConfigurationInterchange.encode(configuration)
    #expect(try ConfigurationInterchange.decode(bytes).automation.preferences.showCustomFanSpeed == false)
    #expect(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(automation.preferences)).showCustomFanSpeed == false)
}
