import Foundation
import Testing
@testable import FandyCore

@Test func updatePreferencesDecodeOldFilesAndRoundTrip() throws {
    let old = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
    #expect(old.automaticUpdates && old.updateFrequency == .weekly)
    var changed = old; changed.automaticUpdates = false; changed.updateFrequency = .monthly
    let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(changed))
    #expect(restored == changed)
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(AppPreferences.self, from: Data("{\"updateFrequency\":\"arbitrary\"}".utf8))
    }
}
@Test func updateIntervalsAndTwoWeekReminderUseDeterministicClock() {
    let epoch = Date(timeIntervalSince1970: 1_000)
    var preferences = AppPreferences(); preferences.updateFrequency = .never
    let automatic = UpdatePolicy(preferences)
    #expect(automatic.checksEnabled && automatic.interval == 604_800)
    #expect(!automatic.checkIsDue(lastCheck: epoch, now: epoch.addingTimeInterval(604_799)))
    #expect(automatic.checkIsDue(lastCheck: epoch, now: epoch.addingTimeInterval(604_800)))
    #expect(!UpdatePolicy.reminderIsDue(downloadedAt: epoch, now: epoch.addingTimeInterval(1_209_599)))
    #expect(UpdatePolicy.reminderIsDue(downloadedAt: epoch, now: epoch.addingTimeInterval(1_209_600)))
    preferences.automaticUpdates = false
    #expect(!UpdatePolicy(preferences).checkIsDue(lastCheck: nil, now: epoch))
    for frequency in [UpdateFrequency.daily, .weekly, .monthly] {
        preferences.updateFrequency = frequency
        #expect(UpdatePolicy(preferences).interval == frequency.interval)
        #expect(UpdatePolicy(preferences).checkIsDue(lastCheck: nil, now: epoch))
        #expect(!UpdatePolicy(preferences).checkIsDue(lastCheck: epoch, now: epoch.addingTimeInterval(-1)))
    }
}
@MainActor @Test func updatePreparationDeduplicatesAndRetriesFailure() async throws {
    var attempts = 0
    var fail = true
    let preparation = UpdatePreparation {
        attempts += 1
        await Task.yield()
        if fail { throw ControlError.restorationUnverified }
    }
    do { try await preparation.prepare(); Issue.record("Failed release authorized installation") } catch {}
    #expect(!preparation.ready && attempts == 1)
    fail = false
    let first = Task { try await preparation.prepare() }
    let second = Task { try await preparation.prepare() }
    try await first.value; try await second.value
    #expect(preparation.ready && attempts == 2)
    try await preparation.prepare()
    #expect(attempts == 2)
}
@Test func olderHelperStatusDoesNotInventBuildIdentity() throws {
    let status = try JSONDecoder().decode(HelperStatus.self, from: JSONEncoder().encode(HelperStatus(automaticVerified: true)))
    #expect(status.helperBuild == nil)
    var current = status; current.helperBuild = FandyBuild.identifier
    #expect(try JSONDecoder().decode(HelperStatus.self, from: JSONEncoder().encode(current)).helperBuild == "12")
}
