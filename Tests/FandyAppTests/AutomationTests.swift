import Foundation
import AppKit
import Testing
import FandyCore
@testable import FandyApp

@MainActor private func makeAutomationModel(_ url: URL) -> AppModel {
    AppModel(storeURL: url, autoStart: false, simulation: true,
             wallClock: { ISO8601DateFormatter().date(from: "2026-10-05T10:00:00Z")! }, clock: { 100 })
}
@MainActor @Test func explicitSelectionSuppressesScheduleUntilResume() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    model.automation.periods = [WeeklyPeriod(profileID: "gaming", weekday: 1, startMinute: 0, endMinute: 1440)]
    model.select("max"); for _ in 0..<6 { await model.tick() }
    #expect(model.machine.selected.id == "max"); #expect(model.manualIntent?.profileID == "max")
    model.resumeSchedule(); for _ in 0..<10 { await Task.yield(); await model.tick() }
    #expect(model.manualIntent == nil); #expect(model.machine.selected.id == "gaming")
    #expect(model.machine.state == .customActive); #expect(model.scheduledPeriodID != nil)
    model.select("system"); for _ in 0..<4 { await model.tick() }
    #expect(model.machine.selected.id == "system"); #expect(model.manualIntent?.profileID == "system")
}
@MainActor @Test func expiredTimerRestoresBeforeAnyFurtherControlStep() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    model.select("max"); for _ in 0..<4 { await model.tick() }; #expect(model.machine.state == .customActive)
    model.activateFor(seconds: 300); #expect(model.activationDeadline == 400)
    model.activationDeadline = 100
    await model.tick(); for _ in 0..<4 { await Task.yield() }
    #expect(model.machine.selected.id == "system"); #expect(model.machine.state == .system)
    #expect(model.manualIntent == nil); #expect(model.snapshot?.fans.allSatisfy { $0.mode == .automatic } == true)
}
@MainActor @Test func durationValidationCannotChangeCurrentIntentAndNewClickCancelsTimer() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json")); model.select("max")
    for invalid in [Double.nan, .infinity, -1, 0, 32 * 86400] { model.activateFor(seconds: invalid); #expect(model.activationDeadline == nil) }
    model.activateFor(seconds: 300); #expect(model.activationDeadline == 400)
    model.select("school"); #expect(model.activationDeadline == nil); #expect(model.manualIntent?.limit == .forever)
}
@MainActor @Test func processExitUsesExactIdentityAndReleasesToSystem() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json")); model.select("max")
    for _ in 0..<3 { await model.tick() }
    let pid = ProcessInfo.processInfo.processIdentifier
    let instance = ProcessCatalog.list(includeHelpers: true).first { $0.pid == pid }
    #expect(instance != nil)
    if let instance { model.activateWhile(instance); #expect(model.manualIntent?.limit == .process(pid: pid, launched: instance.launched)) }
    model.manualIntent = ActivationIntent(profileID: "max", limit: .process(pid: pid, launched: .distantPast))
    await model.tick(); for _ in 0..<4 { await Task.yield() }
    #expect(model.machine.selected.id == "system"); #expect(model.manualIntent == nil)
}
@MainActor @Test func sleepClearsTemporaryAuthorityAndPersistenceNeverRestartsIt() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("profiles.json"), model = makeAutomationModel(url)
    model.select("max"); model.activateFor(seconds: 600); model.powerTransition()
    for _ in 0..<4 { await Task.yield() }
    #expect(model.manualIntent == nil); #expect(model.activationDeadline == nil); #expect(model.machine.selected.id == "system")
    await model.prepareForTermination()
    let next = makeAutomationModel(url); #expect(next.machine.selected.id == "system"); #expect(next.manualIntent == nil)
}
@MainActor @Test func skippedImportConflictsRetainUncontestedEntries() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    let incumbent = WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 500, endMinute: 900)
    model.automation.periods = [incumbent]
    let conflicting = WeeklyPeriod(profileID: "gaming", weekday: 1, startMinute: 600, endMinute: 700)
    let clear = WeeklyPeriod(profileID: "gaming", weekday: 2, startMinute: 600, endMinute: 700)
    model.reviewPeriods([conflicting, clear]); #expect(model.scheduleReview?.conflict.count == 1)
    model.resolveScheduleConflict(override: false, all: true); await model.waitForCollection()
    #expect(model.automation.periods == [incumbent, clear]); #expect(model.scheduleReview == nil)
}
@MainActor @Test func eachConflictCanBeOverriddenIndividuallyBeforeAtomicCommit() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    let left = WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 500, endMinute: 600)
    let right = WeeklyPeriod(profileID: "gaming", weekday: 1, startMinute: 600, endMinute: 900)
    model.automation.periods = [left, right]
    let incoming = WeeklyPeriod(profileID: "max", weekday: 1, startMinute: 550, endMinute: 700)
    model.reviewPeriods([incoming]); #expect(model.scheduleReview?.conflict.count == 2)
    model.overrideScheduleConflict(left.id); #expect(model.scheduleReview?.conflict.count == 1)
    #expect(model.automation.periods == [left, right])
    model.overrideScheduleConflict(right.id); await model.waitForCollection()
    #expect(model.scheduleReview == nil)
    #expect(model.automation.periods.map { [$0.startMinute, $0.endMinute] } == [[500,550],[700,900],[550,700]])
}
@MainActor @Test func allSettingsImportReplacesConfigurationButNotControlAuthority() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    model.create(); await model.waitForCollection(); #expect(model.profiles.count == 7)
    model.select("max"); for _ in 0..<3 { await model.tick() }; model.activateFor(seconds: 60)
    var automation = AutomationConfiguration(); automation.preferences.use24HourTime = false; automation.preferences.launchAtLogin = false
    model.importConfiguration(try ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: automation)))
    await model.waitForCollection(); for _ in 0..<3 { await Task.yield() }
    #expect(model.profiles.count == 6); #expect(model.automation == automation)
    #expect(model.machine.selected.id == "system"); #expect(model.manualIntent == nil)
    let loaded = ProfileStore(url: dir.appendingPathComponent("profiles.json")).load(); #expect(loaded.automation == automation)
}
@MainActor @Test func scheduledSensorFailureDoesNotRetryTheSameOccurrence() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    let period = WeeklyPeriod(profileID: "gaming", weekday: 1, startMinute: 0, endMinute: 1440)
    model.automation.periods = [period]
    for _ in 0..<10 { await Task.yield(); await model.tick() }
    #expect(model.machine.selected.id == "gaming")
    model.scenario = .sensorFailure; await model.tick()
    model.scenario = .comfortableSchool; for _ in 0..<10 { await model.tick() }
    #expect(model.machine.selected.id == "system"); #expect(model.blockedScheduleID == period.id)
}
@MainActor @Test func menuStructureUsesNativeItemsAndDefaultForever() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    let status = StatusMenu(model: model, install: false); let menu = NSMenu(); status.rebuild(menu)
    let timing = menu.items.first { $0.title == "Activate for/until" }?.submenu
    #expect(timing?.items.compactMap(\.submenu).map(\.title) == ["Minutes", "Hours", "Other Time/Until", "While App Is Running"])
    let minutes = timing?.items[0].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title)
    #expect(minutes == stride(from: 5, through: 55, by: 5).map { "\($0) minutes" })
    #expect(timing?.items[1].submenu?.items.filter { !$0.isSeparatorItem }.count == 13)
    #expect(model.automation.preferences.use24HourTime); #expect(model.automation.preferences.launchAtLogin)
}
@MainActor @Test func reenablingAndEditingAnExistingRangeDoesNotDuplicateItsIdentity() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    var original = WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 500, endMinute: 600, enabled: false)
    model.automation.periods = [original]; original.enabled = true
    model.reviewPeriods([original]); await model.waitForCollection()
    #expect(model.automation.periods == [original])
    original.weekday = 2; original.startMinute = 550
    model.reviewPeriods([original]); await model.waitForCollection()
    #expect(model.automation.periods == [original]); #expect(model.draftError == nil)
}
@MainActor @Test func skipAfterPartialOverrideRestoresThatEntryTransaction() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    let left = WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 500, endMinute: 600)
    let right = WeeklyPeriod(profileID: "gaming", weekday: 1, startMinute: 600, endMinute: 900)
    model.automation.periods = [left, right]
    model.reviewPeriods([WeeklyPeriod(profileID: "max", weekday: 1, startMinute: 550, endMinute: 700)])
    model.overrideScheduleConflict(left.id); model.resolveScheduleConflict(override: false); await model.waitForCollection()
    #expect(model.automation.periods == [left, right])
}
@MainActor @Test func skippingConflictedEditPreservesItsOriginalRange() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    let original = WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 500, endMinute: 600)
    let other = WeeklyPeriod(profileID: "gaming", weekday: 1, startMinute: 600, endMinute: 900)
    model.automation.periods = [original, other]
    var edited = original; edited.endMinute = 700
    model.reviewPeriods([edited]); model.resolveScheduleConflict(override: false); await model.waitForCollection()
    #expect(Set(model.automation.periods.map(\.id)) == [original.id, other.id])
    #expect(model.automation.periods.contains(original))
}
@MainActor @Test func scheduleImportStorageFailureDoesNotPublishTheReview() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let blocker = dir.appendingPathComponent("blocked"); try Data("file".utf8).write(to: blocker)
    let model = makeAutomationModel(blocker.appendingPathComponent("profiles.json"))
    model.reviewPeriods([WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 500, endMinute: 600)])
    await model.waitForCollection()
    #expect(model.automation.periods.isEmpty); #expect(model.saveError != nil)
}
@MainActor @Test func preferenceMutationCannotRaceAnAtomicCollectionCommit() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json")); model.create()
    model.setPreferences { $0.use24HourTime = false }
    #expect(model.automation.preferences.use24HourTime)
    await model.waitForCollection()
}
@MainActor @Test func timerAdoptionPreservesAcknowledgedStateAndGeneration() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    model.select("school"); for _ in 0..<8 { await model.tick() }
    let generation = model.machine.generation, state = model.machine.state, idle = model.machine.automaticAtIdle
    model.activateFor(seconds: 3600)
    #expect(model.machine.generation == generation); #expect(model.machine.state == state)
    #expect(model.machine.automaticAtIdle == idle); #expect(model.activationDeadline == 3700)
    model.activateForever(); #expect(model.activationDeadline == nil); #expect(model.machine.generation == generation)
}
@MainActor @Test func failedScheduleCommitCanRetryWithoutPublishingEarly() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let blocker = dir.appendingPathComponent("blocked"); try Data("file".utf8).write(to: blocker)
    let model = makeAutomationModel(blocker.appendingPathComponent("profiles.json"))
    let rule = WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 500, endMinute: 600)
    model.reviewPeriods([rule]); await model.waitForCollection()
    #expect(model.automation.periods.isEmpty); #expect(model.saveError != nil)
    try FileManager.default.removeItem(at: blocker)
    model.save(); await model.waitForCollection()
    #expect(model.automation.periods == [rule]); #expect(model.saveError == nil)
}
private final class AutomationClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 100
    func now() -> Double { lock.withLock { value } }
    func set(_ next: Double) { lock.withLock { value = next } }
}
private actor DelayedAutomationClient: PrivilegedFanClient {
    let clock: AutomationClock
    private var gate: CheckedContinuation<Void, Never>?
    private var delayNext = false
    private var mode: FanMode = .automatic
    private var applyCount = 0
    init(clock: AutomationClock) { self.clock = clock }
    func delay() { delayNext = true }
    func waiting() -> Bool { gate != nil }
    func release() { gate?.resume(); gate = nil }
    func commands() -> Int { applyCount }
    func status() async -> HelperStatus {
        if delayNext { delayNext = false; await withCheckedContinuation { gate = $0 } }
        return HelperStatus(automaticVerified: mode == .automatic, manualQualified: true,
            snapshot: HardwareSnapshot(at: clock.now(), sensors: [], fans: [Fan(id: 0, min: 2000, max: 8000, actual: 3000, mode: mode)]))
    }
    func apply(_ targets: [FanTarget], generation: UInt64) { mode = .manual; applyCount += 1 }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) { mode = .manual; applyCount += 1 }
    func restoreAutomatic() { mode = .automatic }
}
@MainActor @Test func timerExpiringDuringAcquisitionRejectsTheLateReadingBeforeWrite() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = AutomationClock(), client = DelayedAutomationClient(clock: clock)
    let capabilities = HardwareCapabilities(model: "fixture", stage: .maximumControl, topology: .verified, automaticRestoration: .verified, manualTransaction: .verified)
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, client: client, capabilities: capabilities, helperAvailable: { true }, clock: clock.now)
    await model.tick(); model.select("max"); await model.tick(); #expect(model.machine.state == .customActive)
    model.activateFor(seconds: 5); let before = await client.commands()
    await client.delay(); let reading = Task { await model.tick() }
    while !(await client.waiting()) { await Task.yield() }
    clock.set(106); await client.release(); await reading.value
    for _ in 0..<5 { await Task.yield() }
    #expect(await client.commands() == before); #expect(model.machine.selected.id == "system")
    #expect(model.manualIntent == nil); #expect(model.machine.state == .system)
}
@MainActor @Test func rawDisplaySelectionNeverChangesProfileEligibilityOrRequiredSensors() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let capabilities = HardwareCapabilities(model: "unqualified")
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, capabilities: capabilities, helperAvailable: { false })
    let before = model.capabilities
    model.setPreferences { $0.menuSensors = ["key:Tp00", "group:tp-region"] }
    #expect(model.capabilities == before); #expect(!model.canActivate(BuiltInProfiles.school))
    #expect(model.machine.selected.id == "system")
}
@MainActor @Test func selectedDisplayReadingsKeepEstimatesAndMissingKeysExplicit() async {
    let display = SensorMenuModel()
    let snapshot = HardwareSnapshot(at: 100, sensors: [SensorReading(.cpuAverage, 48, at: 100, health: .unverified)], fans: [])
    await display.refresh(selected: ["role:cpuAverage", "key:missing"], simulation: true, snapshot: snapshot)
    #expect(display.displayed["role:cpuAverage"] == "48.0°C · estimate")
    #expect(display.displayed["key:missing"] == "Unavailable on this Mac")
    await display.refresh(selected: ["role:gpuAverage"], simulation: true, snapshot: snapshot)
    #expect(display.displayed["role:gpuAverage"] == "Unavailable")
}
@MainActor @Test func importingBuiltinScheduleNeverCancelsAnExistingManualDuration() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    model.select("school"); for _ in 0..<8 { await model.tick() }; model.activateFor(seconds: 600)
    let intent = model.manualIntent, deadline = model.activationDeadline
    var source = BuiltInProfiles.school; source.floor = 30
    var automation = AutomationConfiguration()
    automation.periods = [WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 0, endMinute: 1440)]
    model.importProfiles(try ScheduledProfileInterchange.encode(source, automation: automation))
    await model.waitForCollection()
    #expect(model.manualIntent == intent); #expect(model.activationDeadline == deadline)
    #expect(model.machine.selected.id == "school"); #expect(model.machine.selected.floor == 30)
    #expect(model.automation.periods.count == 1)
}
@MainActor @Test func importingSystemScheduleDoesNotCreateAnIndefiniteManualOverride() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    var automation = AutomationConfiguration(); automation.periods = [WeeklyPeriod(profileID: "system", weekday: 1, startMinute: 0, endMinute: 1440)]
    model.importProfiles(try ScheduledProfileInterchange.encode(BuiltInProfiles.system, automation: automation))
    await model.waitForCollection(); #expect(model.manualIntent == nil)
    for _ in 0..<5 { await model.tick(); await Task.yield() }
    #expect(model.scheduledPeriodID == model.automation.periods.first?.id)
    #expect(model.machine.selected.id == "system")
}
@MainActor @Test func aNewManualSelectionDuringConfigurationSaveOutranksImportedSchedules() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = makeAutomationModel(dir.appendingPathComponent("profiles.json"))
    var automation = AutomationConfiguration()
    automation.periods = [WeeklyPeriod(profileID: "gaming", weekday: 1, startMinute: 0, endMinute: 1440)]
    model.importConfiguration(try ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: automation)))
    model.select("max")
    await model.waitForCollection(); for _ in 0..<5 { await model.tick() }
    #expect(model.manualIntent?.profileID == "max"); #expect(model.machine.selected.id == "max")
    #expect(model.scheduledPeriodID == nil)
}
