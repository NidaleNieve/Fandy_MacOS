import Foundation
import AppKit
import SwiftUI
import Testing
@testable import FandyCore
@testable import FandyApp

@MainActor @Test func cancellationWrapsFullTitleWhileOtherActionsRetainNativeRowsAndBoundedWidth() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    // Keep this native-row case outside Monday's schedule, regardless of test date.
    let sunday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10))!
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: { sunday })
    var school = BuiltInProfiles.school; school.name = String(String(repeating: "A very long school profile ", count: 4).prefix(80)); model.update(school)
    var automation = model.automation; automation.periods = [.init(profileID: "gaming", weekday: 1, startMinute: 0, endMinute: 1440)]
    model.setAutomation(automation); model.select("school"); model.activateFor(seconds: 300)
    let menu = NSMenu(), presenter = StatusMenu(model: model, install: false)
    for _ in 0..<8 {
        presenter.rebuild(menu)
        #expect(menu.items.filter { $0.action != nil && $0.toolTip != model.cancellationTitle }.allSatisfy { $0.view == nil })
        #expect(menu.size.width <= MenuLayout.maximumMenuWidth)
        #expect(menu.items.compactMap(\.view).allSatisfy { ($0 as? NSHostingView<FanMenuStatus>)?.sizingOptions.isEmpty ?? true })
    }
    let cancel = try #require(menu.items.first { $0.toolTip == model.cancellationTitle })
    #expect(cancel.view?.frame.width == MenuLayout.width)
    #expect(cancel.accessibilityLabel() == model.cancellationTitle)
}
@MainActor @Test func profileHostsDoNotGrowToChangingContentAndHideNativeScrollIndicators() {
    let hosting = ProfileHostingController(rootView: Text("Wide content"))
    _ = hosting.view
    #expect(hosting.sizingOptions.isEmpty)
    let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
    let nested = NSView(); nested.addSubview(scroll)
    ProfileHostingController<Text>.hideScrollIndicators(in: nested)
    #expect(!scroll.hasVerticalScroller && !scroll.hasHorizontalScroller)
    // Scrolling remains available: only the indicators, not content, are removed.
    #expect(scroll.contentView != nil)
}
@Test func weeklyOverviewSplitsOvernightAcrossWeekBoundaryAndExcludesDisabledPeriods() {
    let sunday = WeeklyPeriod(profileID: "gaming", weekday: 7, startMinute: 1110, endMinute: 145)
    let monday = WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 510, endMinute: 750)
    let disabled = WeeklyPeriod(profileID: "max", weekday: 1, startMinute: 0, endMinute: 30, enabled: false)
    let rows = ScheduleOverviewRow.rows(day: 1, periods: [monday, disabled, sunday])
    #expect(rows.map(\.profileID) == ["gaming", "school"])
    #expect(rows[0].start == 0 && rows[0].end == 145 && rows[0].continued)
    let ending = ScheduleOverviewRow.rows(day: 7, periods: [sunday])
    #expect(ending.count == 1 && ending[0].end == 1440 && !ending[0].continued)
    #expect(ScheduleOverviewRow.rows(day: 8, periods: [monday]).isEmpty)
}
@MainActor @Test func launchRuleActivatesOnlyOnNewProcessThenClosesAndResumesSchedule() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["30"]; try process.run()
    defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
    let observed = try #require(ProcessCatalog.list(includeHelpers: true).first { $0.pid == process.processIdentifier })
    let app = RunningProcess(pid: observed.pid, launched: observed.launched, name: "Game", bundleID: "example.game", icon: nil)
    var catalog: [RunningProcess] = []
    let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: { date }, applicationCatalog: { catalog })
    var rule = ProfileActivationDefault(); rule.launchWhenOpened = true; rule.kind = .application
    rule.applicationID = "example.game"; rule.applicationName = "Game"; model.setActivationDefault(rule, profileID: "gaming")
    var config = model.automation; config.periods = [.init(profileID: "school", weekday: 1, startMinute: 500, endMinute: 750)]; model.setAutomation(config)
    for _ in 0..<6 { await model.tick() }
    #expect(model.machine.selected.id == "school")
    catalog = [app]; model.refreshApplicationAvailability(force: true); model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "gaming" && model.watchedProcessName == "Game")
    model.activateFor(seconds: 600); model.refreshApplicationAvailability(force: true); model.evaluateApplicationLaunches()
    #expect(model.activationDeadline != nil) // Further polls never reset a menu duration.
    model.activateWhile(app); process.terminate(); process.waitUntilExit(); catalog = []
    for _ in 0..<8 { await model.tick() }
    #expect(model.manualIntent == nil && model.machine.selected.id == "school")
}
@MainActor @Test func existingAppStartupAndManualOverrideSuppressLaunchRules() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["30"]; try process.run()
    defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
    let observed = try #require(ProcessCatalog.list(includeHelpers: true).first { $0.pid == process.processIdentifier })
    let app = RunningProcess(pid: observed.pid, launched: observed.launched, name: "Game", bundleID: "example.game", icon: nil)
    var catalog = [app]
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, applicationCatalog: { catalog })
    var rule = ProfileActivationDefault(); rule.launchWhenOpened = true; rule.applicationID = "example.game"; rule.applicationName = "Game"
    model.setActivationDefault(rule, profileID: "gaming"); model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "system")
    catalog = []; model.refreshApplicationAvailability(force: true)
    model.select("max"); model.activateFor(seconds: 300); let deadline = model.activationDeadline
    catalog = [app]; model.refreshApplicationAvailability(force: true); model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "max" && model.activationDeadline == deadline && model.pendingApplicationLaunches.isEmpty)
    model.powerTransition(); model.refreshApplicationAvailability(force: true); model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "system")
}
@Test func launchRulesArePortableAndOldArchivesDecodeDisabled() throws {
    let old = try JSONDecoder().decode(ProfileActivationDefault.self, from: Data(#"{"kind":"forever","seconds":300,"applicationID":"","applicationName":""}"#.utf8))
    #expect(!old.launchWhenOpened)
    var rule = ProfileActivationDefault(); rule.launchWhenOpened = true; rule.kind = .application; rule.applicationID = "example.game"; rule.applicationName = "Game"
    var config = AutomationConfiguration(); config.activationDefaults["gaming"] = rule
    let full = try ConfigurationInterchange.decode(ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: config)))
    #expect(full.automation.activationDefaults["gaming"] == rule)
    let individual = try ScheduledProfileInterchange.decode(ScheduledProfileInterchange.encode(BuiltInProfiles.gaming, automation: config), existingCount: 6)
    #expect(individual.activationDefaults["gaming"] == rule)
    rule.applicationID = ""; #expect(throws: ScheduleError.self) { try rule.validate() }
    rule.applicationID = "example.game\n"; #expect(throws: ScheduleError.self) { try rule.validate() }
}
@MainActor @Test func timeMenuUsesCompactDurationAndUpdatesHeightWithoutGrowingWidth() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let menu = NSMenu(), presenter = StatusMenu(model: model, install: false); presenter.rebuild(menu)
    let time = try #require(menu.items.first { $0.title == "Activate for/until" }?.submenu?.items.first { $0.title == "Other Time/Until" }?.submenu?.items.first?.view)
    #expect(time.frame.width == 220 && time.frame.height < 210)
    let host = MenuControlHostingView(rootView: Text("For").frame(width: 220, height: 80))
    host.frame.size = host.fittingSize
    host.rootView = Text("Until").frame(width: 220, height: 190)
    host.layout()
    #expect(host.frame.width == 220 && host.frame.height == 190)
    host.rootView = Text("For").frame(width: 220, height: 80)
    host.layout()
    #expect(host.frame.width == 220 && host.frame.height == 80)
    let clock = TimeDial.makePicker()
    #expect(clock.intrinsicContentSize.width > 0 && clock.intrinsicContentSize.height > 0)
}
@MainActor @Test func unavailableLaunchProfileCannotActivateAndTriggerEditsUndo() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false)
    var rule = ProfileActivationDefault(); rule.launchWhenOpened = true; rule.applicationID = "example.game"; rule.applicationName = "Game"
    model.editorHistory.groupsByEvent = false
    model.editorHistory.beginUndoGrouping(); model.setActivationDefault(rule, profileID: "gaming"); model.editorHistory.endUndoGrouping()
    model.pendingApplicationLaunches = ["example.game"]; model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "system" && model.pendingApplicationLaunches.isEmpty)
    model.pendingApplicationLaunches = ["example.game"]; model.automationFailed()
    #expect(model.pendingApplicationLaunches.isEmpty)
    model.editorHistory.undo(); #expect(model.automation.activationDefaults["gaming"] == nil)
    model.editorHistory.redo(); #expect(model.automation.activationDefaults["gaming"]?.launchWhenOpened == true)
}

@MainActor @Test func waitingApplicationReusesOneCatalogSnapshotAcrossATick() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var reads = 0
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, simulation: true,
                         applicationCatalog: { reads += 1; return [] }, clock: { 10 })
    var rule = ProfileActivationDefault(); rule.kind = .application; rule.applicationID = "example.waiting"; rule.applicationName = "Waiting"
    model.setActivationDefault(rule, profileID: "gaming")
    model.select("gaming")
    #expect(model.awaitingApplicationID == "example.waiting")
    let beforeTick = reads
    await model.tick(); model.expireActivation(); model.expireActivation()
    #expect(reads == beforeTick && model.awaitingApplicationID == "example.waiting")
    model.refreshApplicationAvailability(force: true)
    #expect(reads == beforeTick + 1)
    await model.prepareForTermination()
}

@MainActor @Test func scheduledSelectionDoesNotSaveDefinitionsOrRememberAnActiveLease() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true)
    model.select("gaming", manual: false)
    await Task.yield(); await Task.yield()
    #expect(model.machine.selected.id == "gaming")
    #expect(model.automation.preferences.defaultProfileID == "system")
    #expect(!FileManager.default.fileExists(atPath: url.path))
    await model.prepareForTermination()
    #expect(ProfileStore(url: url).load().automation.preferences.defaultProfileID == "system")
}
