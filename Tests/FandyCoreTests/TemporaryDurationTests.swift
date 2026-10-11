import Foundation
import Testing
@testable import FandyCore

@Test func temporaryDurationDefaultsAndConfigurationRoundTrip() throws {
    #expect(AppPreferences().customFanSpeedDurationMinutes == 5)
    #expect(try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8)).customFanSpeedDurationMinutes == 5)
    var config = AutomationConfiguration()
    config.preferences.customFanSpeedDurationMinutes = 75
    config.preferences.showActivationTiming = false
    let imported = try ConfigurationInterchange.decode(ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: config)))
    #expect(imported.automation.preferences == config.preferences)
}

@Test func temporaryDurationValidationRejectsUnboundedOrMalformedPreferences() throws {
    for value in [0, -1, 44_641, Int.max] {
        var config = AutomationConfiguration(); config.preferences.customFanSpeedDurationMinutes = value
        #expect(throws: ScheduleError.self) { try config.validate(profileIDs: Set(BuiltInProfiles.all.map(\.id))) }
    }
    for value in [1, 44_640] {
        var config = AutomationConfiguration(); config.preferences.customFanSpeedDurationMinutes = value
        try config.validate(profileIDs: Set(BuiltInProfiles.all.map(\.id)))
    }
    for value in ["1.5", "\"15\"", "1e308"] {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AppPreferences.self, from: Data("{\"customFanSpeedDurationMinutes\":\(value)}".utf8))
        }
    }
}
