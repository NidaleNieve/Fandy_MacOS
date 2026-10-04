import AppKit
import Foundation
import ServiceManagement
import Testing
@testable import FandyCore
@testable import FandyApp

private final class ScheduleClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ date: Date) { lock.lock(); value = date; lock.unlock() }
}
@MainActor @Test func ordinaryProfileSurvivesQuitButOnlyReactivatesAfterStartupChecks() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<5 { await model.tick() }
    #expect(model.isSelected("cool-chassis") && model.manualIntent == nil)
    await model.prepareForTermination()
    #expect(model.machine.selected.id == "system")
    let next = AppModel(storeURL: url, autoStart: false, simulation: true)
    #expect(next.machine.selected.id == "system" && next.automation.preferences.defaultProfileID == "cool-chassis")
    for _ in 0..<6 { await next.tick() }
    #expect(next.isSelected("cool-chassis") && next.manualIntent == nil)
}
@MainActor @Test func scheduledRangesReturnToTheRememberedProfileIncludingGaps() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = ScheduleClock(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!)
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: clock.now)
    model.select("cool-chassis")
    var config = model.automation
    config.periods = [.init(profileID: "school", weekday: 1, startMinute: 510, endMinute: 750), .init(profileID: "gaming", weekday: 1, startMinute: 840, endMinute: 900)]
    model.setAutomation(config)
    for (minutes, expected) in [(480,"cool-chassis"),(510,"school"),(750,"cool-chassis"),(840,"gaming"),(900,"cool-chassis")] {
        clock.set(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: minutes / 60, minute: minutes % 60))!)
        for _ in 0..<8 { await model.tick() }
        #expect(model.isSelected(expected))
        #expect(model.automation.preferences.defaultProfileID == "cool-chassis")
    }
}
@MainActor @Test func untilChangedTogglePinsAndUnpinsWithoutLosingBackgroundProfile() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: { date })
    model.select("cool-chassis"); model.activateForever()
    var config = model.automation; config.periods = [.init(profileID: "school", weekday: 1, startMinute: 540, endMinute: 660)]; model.setAutomation(config)
    for _ in 0..<5 { await model.tick() }
    #expect(model.isSelected("cool-chassis") && model.manualIntent?.limit == .forever)
    let menu = NSMenu(), presenter = StatusMenu(model: model, install: false); presenter.rebuild(menu)
    #expect(menu.items.first { $0.title == "Activate for/until" }?.submenu?.items.first { $0.title == "Until Changed" }?.state == .on)
    model.activateForever(); for _ in 0..<8 { await model.tick() }
    #expect(model.manualIntent == nil && model.isSelected("school"))
    #expect(model.automation.preferences.defaultProfileID == "cool-chassis")
    presenter.rebuild(menu)
    #expect(menu.items.first { $0.title == "Activate for/until" }?.submenu?.items.first { $0.title == "Until Changed" }?.state == .off)
}
@MainActor @Test func temporaryActivationDoesNotBecomeAnUnboundedStartupDefault() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<4 { await model.tick() }
    model.select("max"); model.activateFor(seconds: 300)
    #expect(model.automation.preferences.defaultProfileID == "cool-chassis")
    await model.prepareForTermination()
    let next = AppModel(storeURL: url, autoStart: false, simulation: true)
    for _ in 0..<6 { await next.tick() }
    #expect(next.isSelected("cool-chassis") && next.manualIntent == nil)
}
@MainActor @Test func failedInputsBlockRememberedResumeAndDeletionResetsItsIdentifier() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<4 { await model.tick() }
    model.scenario = .sensorFailure; await model.tick()
    model.scenario = .comfortableSchool; for _ in 0..<8 { await model.tick() }
    #expect(model.machine.selected.id == "system" && model.defaultResumeBlocked)
    model.create(); await model.waitForCollection(); let custom = model.editorSelection
    model.select(custom); for _ in 0..<4 { await model.tick() }
    model.delete(custom); await model.waitForCollection()
    #expect(model.automation.preferences.defaultProfileID == "system")
}
@MainActor @Test func missingApprovalDisablesCustomRowsAndAddsVisibleRecoveryActions() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let capabilities = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, capabilities: capabilities,
                         helperAvailable: { false }, helperRegistrationStatus: { .requiresApproval })
    #expect(model.needsHelperSetup && model.helperSetupMessage.contains("Background App Activity"))
    let menu = NSMenu(), presenter = StatusMenu(model: model, install: false); presenter.rebuild(menu)
    let rows = menu.items.filter { model.profiles.map(\.name).contains($0.title) }
    #expect(rows.filter { $0.title != "System" }.allSatisfy { !$0.isEnabled && $0.image != nil })
    #expect(rows.first { $0.title == "System" }?.isEnabled == true)
    #expect(menu.items.contains { $0.toolTip == "Allow Fan Control…" && $0.image != nil && $0.isEnabled })
    model.select("max"); #expect(model.machine.selected.id == "system")
}
@Test func rememberedProfilePreferenceIsBackwardCompatiblePortableAndValidated() throws {
    let old = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
    #expect(old.defaultProfileID == "system")
    var config = AutomationConfiguration(); config.preferences.defaultProfileID = "cool-chassis"
    let portable = try ConfigurationInterchange.decode(ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: config)))
    #expect(portable.automation.preferences.defaultProfileID == "cool-chassis")
    config.preferences.defaultProfileID = "missing"; #expect(throws: ScheduleError.self) { try config.validate(profileIDs: Set(BuiltInProfiles.all.map(\.id))) }
}

@MainActor @Test func explicitSystemSelectionCannotBeUndoneByTheCurrentScheduledOccurrence() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = ScheduleClock(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!)
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: clock.now)
    var config = model.automation
    config.periods = [.init(profileID: "school", weekday: 1, startMinute: 510, endMinute: 750), .init(profileID: "school", weekday: 1, startMinute: 840, endMinute: 900)]
    model.setAutomation(config)
    for _ in 0..<6 { await model.tick() }
    #expect(model.isSelected("school"))
    model.select("system"); for _ in 0..<6 { await model.tick() }
    #expect(model.isSelected("system") && model.blockedScheduleID != nil)
    clock.set(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 14))!)
    for _ in 0..<6 { await model.tick() }
    #expect(model.isSelected("school") && model.blockedScheduleID == nil)
}
@MainActor @Test func activeScheduleAtReopenRetainsTheDefaultForItsEnd() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("profiles.json")
    let clock = ScheduleClock(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!)
    var config = AutomationConfiguration(); config.preferences.defaultProfileID = "cool-chassis"
    config.periods = [.init(profileID: "school", weekday: 1, startMinute: 510, endMinute: 750)]
    try ProfileStore(url: url).save(BuiltInProfiles.all, previousSelection: "system", automation: config)
    let model = AppModel(storeURL: url, autoStart: false, simulation: true, wallClock: clock.now)
    #expect(model.machine.selected.id == "system")
    for _ in 0..<6 { await model.tick() }
    #expect(model.isSelected("school"))
    clock.set(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 13))!)
    for _ in 0..<8 { await model.tick() }
    #expect(model.isSelected("cool-chassis") && model.automation.preferences.defaultProfileID == "cool-chassis")
}
@MainActor @Test func reselectingTheSameProfileDuringDuplicationPreservesItsNewDefaultOnDisk() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<5 { await model.tick() }
    model.activateFor(seconds: 300)
    #expect(model.automation.preferences.defaultProfileID == "system")
    model.duplicate("school"); model.select("cool-chassis"); await model.waitForCollection()
    #expect(model.automation.preferences.defaultProfileID == "cool-chassis")
    await model.prepareForTermination()
    #expect(ProfileStore(url: url).load().automation.preferences.defaultProfileID == "cool-chassis")
}
@MainActor @Test func retryingFailedConfigurationDoesNotLoseANewerDefaultSelection() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let blocker = dir.appendingPathComponent("blocked"); try Data("file".utf8).write(to: blocker)
    let url = blocker.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true)
    let period = WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 500, endMinute: 600)
    model.reviewPeriods([period]); await model.waitForCollection()
    #expect(model.saveError != nil)
    try FileManager.default.removeItem(at: blocker)
    model.select("cool-chassis"); await model.waitForCollection()
    #expect(model.automation.periods == [period])
    #expect(model.automation.preferences.defaultProfileID == "cool-chassis")
    await model.prepareForTermination()
    #expect(ProfileStore(url: url).load().automation.preferences.defaultProfileID == "cool-chassis")
}
