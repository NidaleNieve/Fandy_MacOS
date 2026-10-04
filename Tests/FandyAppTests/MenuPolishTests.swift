import Foundation
import AppKit
import SwiftUI
import Testing
@testable import FandyCore
@testable import FandyApp

@MainActor @Test func pendingSelectionIsImmediateAndAcceptsTimerWithoutClaimingControl() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.select("gaming")
    #expect(model.menuSelectionID == "gaming" && model.machine.state == .initializingCustom)
    #expect(!model.isSelected("gaming") && model.canSetActivationLimit)
    model.activateFor(seconds: 300)
    #expect(model.manualIntent?.profileID == "gaming" && model.activationDeadline != nil)
    for _ in 0..<6 { await model.tick() }
    #expect(model.isSelected("gaming") && model.manualIntent?.profileID == "gaming")
}
@MainActor @Test func profileActivationDefaultAndShortcutToggleIntegrateWithManualIntent() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    var rule = ProfileActivationDefault(); rule.kind = .duration; rule.seconds = 300
    model.setActivationDefault(rule, profileID: "max"); model.select("max")
    #expect(model.manualIntent?.profileID == "max" && model.activationDeadline != nil)
    #expect(model.cancellationTitle == "Cancel Max")
    model.activateFor(seconds: 120); let chosen = model.activationDeadline
    await model.tick(); #expect(model.activationDeadline == chosen)
    model.toggleProfile("max"); for _ in 0..<4 { await Task.yield() }
    #expect(model.machine.selected.id == "system")
    model.toggleProfile("max"); #expect(model.manualIntent?.profileID == "max" && model.activationDeadline != nil)
}
@MainActor @Test func missingDefaultApplicationRetainsPreviousProfile() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    var rule = ProfileActivationDefault(); rule.kind = .application; rule.applicationID = "invalid.nonexistent.fandy.test"; rule.applicationName = "Game"
    model.setActivationDefault(rule, profileID: "gaming"); model.select("gaming")
    #expect(model.machine.selected.id == "system" && model.draftError?.contains("not running") == true)
}
@MainActor @Test func universalUndoRestoresCreationDeletionSchedulesAndDefaultsAcrossSelection() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.editorHistory.groupsByEvent = false
    model.editorHistory.beginUndoGrouping(); model.create(); await model.waitForCollection(); model.editorHistory.endUndoGrouping()
    let created = model.editorSelection; #expect(model.profiles.count == 7)
    model.editorSelection = "gaming"; model.editorHistory.undo(); #expect(model.profiles.count == 6)
    model.editorHistory.redo(); #expect(model.profiles.contains { $0.id == created })
    var rule = ProfileActivationDefault(); rule.kind = .duration
    model.editorHistory.beginUndoGrouping(); model.setActivationDefault(rule, profileID: created); model.editorHistory.endUndoGrouping()
    model.editorHistory.beginUndoGrouping(); model.reviewPeriods([WeeklyPeriod(profileID: created, weekday: 1, startMinute: 600, endMinute: 720)]); await model.waitForCollection(); model.editorHistory.endUndoGrouping()
    #expect(model.automation.periods.count == 1)
    model.editorSelection = created
    model.editorHistory.beginUndoGrouping(); model.delete(); await model.waitForCollection(); model.editorHistory.endUndoGrouping()
    #expect(!model.profiles.contains { $0.id == created })
    model.editorHistory.undo(); #expect(model.profiles.contains { $0.id == created })
    #expect(model.automation.periods.count == 1 && model.automation.activationDefaults[created] == rule)
    model.editorHistory.undo(); #expect(model.automation.periods.isEmpty)
    model.editorHistory.undo(); #expect(model.automation.activationDefaults[created] == nil)
}
@Test func observedFanBarIncludesStoppedAutomaticAndDifferentMaximums() {
    #expect(StatusPresentation.observedFanPercent([Fan(id:0,min:2000,max:8000,actual:0)]) == 0)
    #expect(StatusPresentation.observedFanPercent([Fan(id:0,min:2000,max:8000,actual:2000), Fan(id:1,min:1800,max:6000,actual:3000)]) == 50)
    #expect(StatusPresentation.observedFanPercent([Fan(id:0,min:2000,max:8000,actual:9000)]) == 100)
    #expect(StatusPresentation.observedFanPercent([Fan(id:0,min:2000,max:8000,actual:.nan)]) == 0)
}
@Test func curveContextInsertionIsLocalMonotonicAndDeletionProtectsMinimum() throws {
    var draft = CurveDraft(FanCurve(.chip, [(40,0),(60,40),(85,100)]))
    let inserted = draft.add(at: 50, percent: 90); let result = try #require(inserted); try result.validate()
    #expect(result.points[1].temperature == 50 && result.points[1].percent == 40)
    #expect(draft.add(at: 50, percent: 20) == nil)
    #expect(draft.add(at: .nan, percent: 20) == nil)
    _ = draft.remove(); draft.select(draft.curve.points[1].id); _ = draft.remove()
    #expect(draft.curve.points.count == 2 && draft.remove() == nil)
}

private actor StartupRetryClient: PrivilegedFanClient {
    private var count = 0
    func restores() -> Int { count }
    func restoreAutomatic() throws { count += 1; if count == 1 { throw ControlError.restorationUnverified } }
    func status() -> HelperStatus {
        let verified = count >= 2
        let report = RestorationReport(fans: [FanRestorationOutcome(fanID: 0, initialMode: .automatic, commandSucceeded: verified, immediateMode: .automatic, observedMode: .automatic, failure: verified ? nil : "Startup transport transient")])
        return HelperStatus(automaticVerified: verified, snapshot: HardwareSnapshot(at: 10, sensors: [], fans: [Fan(id: 0, min: 2000, max: 8000, actual: 0)]), restoration: report)
    }
    func apply(_ targets: [FanTarget], generation: UInt64) throws { throw ControlError.unauthorized }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) throws { throw ControlError.unauthorized }
}
@MainActor @Test func startupFailedHandbackRetriesAndRecoversWithoutProfileSwitching() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let client = StartupRetryClient()
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, client: client, capabilities: HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified), helperAvailable: { true }, clock: { 10 })
    model.start(); defer { model.stop() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(4))
    while !model.isSelected("system") && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await client.restores() >= 2)
    #expect(model.isSelected("system") && model.hardwareError == nil && model.machine.fault == nil)
}
@MainActor @Test func sidebarNeverCollapsesAndMenuActionsUseNativeRows() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    var profile = BuiltInProfiles.school; profile.name = String(repeating: "Wide profile ", count: 6); model.update(profile)
    let split = ProfileSplitView(sidebar: { Text("Profiles") }, detail: { Text("Editor") }).makeController()
    #expect(split.splitViewItems.allSatisfy { !$0.canCollapse })
    #expect(split.splitViewItems[0].minimumThickness == 220)
    let menu = NSMenu(), presenter = StatusMenu(model: model, install: false); presenter.rebuild(menu)
    #expect(menu.items.filter { $0.view != nil }.allSatisfy { $0.view!.frame.width <= MenuLayout.width })
    let row = try #require(menu.items.first { $0.accessibilityLabel() == profile.name })
    #expect(row.view == nil && row.title.hasSuffix("…"))
    #expect(menu.size.width <= MenuLayout.maximumMenuWidth)
    #expect(menu.items.filter { $0.action != nil && $0.title != profile.name }.allSatisfy { $0.view == nil })
    #expect(menu.items.filter { $0.action != nil && $0.view == nil }.allSatisfy { MenuLayout.titleWidth($0.title) <= MenuLayout.nativeTitleWidth })
}

@MainActor @Test func defaultApplicationTracksItsExactProcessAndReleaseOnExit() async throws {
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["30"]; try process.run()
    defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
    let observed = try #require(ProcessCatalog.list(includeHelpers: true).first { $0.pid == process.processIdentifier })
    let application = RunningProcess(pid: observed.pid, launched: observed.launched, name: "Game", bundleID: "example.game", icon: nil)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, applicationCatalog: { [application] })
    var rule = ProfileActivationDefault(); rule.kind = .application; rule.applicationID = "example.game"; rule.applicationName = "Game"
    model.setActivationDefault(rule, profileID: "gaming"); model.select("gaming")
    #expect(model.watchedProcessName == "Game")
    guard case .process(let pid, let launched) = model.manualIntent?.limit else { Issue.record("Default did not install a process watch"); return }
    #expect(pid == observed.pid && launched == observed.launched)
    process.terminate(); process.waitUntilExit(); model.expireActivation()
    for _ in 0..<5 { await Task.yield() }
    #expect(model.manualIntent == nil && model.machine.selected.id == "system")
}

@MainActor @Test func duplicationCopiesActivationDefaultWithoutDuplicatingGlobalShortcut() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    var rule = ProfileActivationDefault(); rule.kind = .duration; rule.seconds = 300
    model.setActivationDefault(rule, profileID: "max"); model.editorSelection = "max"; model.duplicate(); await model.waitForCollection()
    #expect(model.automation.activationDefaults[model.editorSelection] == rule)
    #expect(model.automation.preferences.shortcuts[model.editorSelection] == nil)
}

@MainActor @Test func deletingAnActiveProfileCannotOverwriteANewerManualSelection() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.create(); await model.waitForCollection(); let custom = model.editorSelection
    model.select(custom); model.delete(); model.select("max"); await model.waitForCollection()
    #expect(!model.profiles.contains { $0.id == custom })
    #expect(model.machine.selected.id == "max" && model.manualIntent?.profileID == "max")
}

@MainActor @Test func cancellingScheduledActivationPausesOccurrenceInsteadOfImmediatelyReactivatingIt() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
    let calendar = Calendar.current
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: { date })
    var config = model.automation; let period = WeeklyPeriod(profileID: "gaming", weekday: 1, startMinute: 600, endMinute: 660); config.periods = [period]
    model.setAutomation(config)
    for _ in 0..<6 { await model.tick() }
    #expect(model.scheduledPeriodID == period.id && model.machine.selected.id == "gaming")
    model.cancelActivation(); for _ in 0..<6 { await model.tick() }
    #expect(model.machine.selected.id == "system" && model.blockedScheduleID == period.id)
    #expect(model.cancellationTitle == "Resume Schedule")
    model.resumeSchedule(); for _ in 0..<6 { await model.tick() }
    #expect(model.machine.selected.id == "gaming" && model.scheduledPeriodID == period.id)
}

@Test func shortcutIDsCannotBeReusedForStaleEventsOrOverflow() {
    var sequence = ShortcutIDSequence()
    let a = sequence.next(), b = sequence.next(); #expect(a == 1 && b == 2)
    // The sequence survives unregistration/config changes, so queued old IDs
    // cannot be rebound to a different profile. Exhaustion requires restart.
    sequence.value = UInt32.max - 1
    #expect(sequence.next() == UInt32.max); #expect(sequence.next() == nil)
    #expect(sequence.value == UInt32.max)
}
