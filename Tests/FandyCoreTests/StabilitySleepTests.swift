import Foundation
import Testing
@testable import FandyCore

@Test func longerResponseWindowsAndDailyDefaultsAreExplicit() throws {
    #expect(BuiltInProfiles.school.responseWindow == 15)
    #expect(abs(BuiltInProfiles.coolChassis.responseWindow - 12) < 0.001)
    #expect(BuiltInProfiles.gaming.responseWindow == 0)
    #expect(AppPreferences().updateFrequency == .daily)
    #expect(try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8)).updateFrequency == .daily)
    for value in ["weekly", "monthly"] {
        #expect(try JSONDecoder().decode(AppPreferences.self, from: Data("{\"updateFrequency\":\"\(value)\"}".utf8)).updateFrequency.rawValue == value)
    }
    let retired = try JSONDecoder().decode(AppPreferences.self, from: Data("{\"updateFrequency\":\"never\"}".utf8))
    #expect(!retired.automaticUpdates && retired.updateFrequency == .daily)
    #expect(!UpdatePolicy(AppPreferences(), suspended: true).checksEnabled)
    #expect(UpdatePolicy(AppPreferences()).checksEnabled)
}
@Test func fifteenSecondAveragingSuppressesBurstsAndReachesFullSustainedDemand() throws {
    var filter = TimeWeightedDemand()
    _ = try filter.update(20, at: 0, window: 15)
    for t in 1...30 {
        let value = try filter.update(t % 5 == 1 ? 80 : 20, at: Double(t), window: 15)
        #expect(value <= 32.01)
    }
    for t in 31...47 { _ = try filter.update(70, at: Double(t), window: 15) }
    #expect(try filter.update(70, at: 48, window: 15) == 70)
    #expect(try filter.update(85, at: 52, window: 15) == 85) // acquisition gap: conservative reset
    #expect(throws: ControlError.invalidNumber) { try filter.update(20, at: 51, window: 15) }
    #expect(throws: ControlError.invalidNumber) { try filter.update(20, at: 53, window: 16) }
}
@Test func helperSleepBarrierRejectsLeasesUntilWakeWithoutSampling() throws {
    let spy = FanSpy()
    var reads = 0
    let helper = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(), read: { reads += 1; return spy.snapshot() }, clock: { spy.now })
    #expect(helper.startup())
    helper.systemWillSleep()
    #expect(helper.powerSuspended)
    let before = reads
    for _ in 0..<6 { _ = helper.status(); helper.watchdog() }
    #expect(reads == before && spy.fans.allSatisfy { $0.mode == .automatic })
    #expect(throws: ControlError.helperUnavailable) { try helper.begin(LeaseRequest(generation: 1, required: []), owner: UUID()) }
    helper.systemDidWake()
    #expect(!helper.powerSuspended && helper.leaseOwner == nil)
    #expect(helper.status().automaticVerified)
}
@Test func partialSleepRestorationRemainsVisibleAndDoesNotGrantControl() throws {
    let spy = FanSpy(); spy.failAuto = 0
    let helper = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(), read: { spy.snapshot() }, clock: { spy.now })
    helper.systemWillSleep()
    #expect(spy.calls == ["auto0", "auto1"])
    #expect(helper.powerSuspended && !helper.status().automaticVerified)
    helper.systemDidWake()
    #expect(throws: (any Error).self) { try helper.begin(LeaseRequest(generation: 1, required: []), owner: UUID()) }
    spy.failAuto = nil; #expect(helper.restore())
    #expect(helper.status().automaticVerified)
}
