import AppKit
import SwiftUI
import ServiceManagement
import Testing
@testable import FandyCore
@testable import FandyApp

@MainActor @Test func profilesWindowCannotCollapseOnCreationLayoutOrProgrammaticResize() {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let window = ProfilesWindow.make(content: ProfileEditor(model: model))
    defer { window.close() }
    #expect(!window.isVisible)
    #expect(window.contentMinSize == ProfilesWindow.minimumContentSize)
    #expect(window.contentRect(forFrameRect: window.frame).size == ProfilesWindow.initialContentSize)
    for id in model.profiles.map(\.id) {
        model.editorSelection = id
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = window.contentRect(forFrameRect: window.frame).size
        #expect(size.width >= 960 && size.height >= 560)
    }
    window.setContentSize(NSSize(width: 20, height: 10))
    #expect(window.contentRect(forFrameRect: window.frame).size.width >= 960)
    #expect(window.contentRect(forFrameRect: window.frame).size.height >= 560)
    window.setFrame(NSRect(x: 0, y: 0, width: 50, height: 30), display: false)
    #expect(window.contentRect(forFrameRect: window.frame).size.width >= 960)
    #expect(window.contentRect(forFrameRect: window.frame).size.height >= 560)
    window.setFrame(NSRect(x: 0, y: 0, width: 60, height: 25), display: false, animate: false)
    #expect(window.contentRect(forFrameRect: window.frame).size.height >= 560)
    window.setContentSize(NSSize(width: 1200, height: 800))
    #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 1200, height: 800))
    #expect(!window.isVisible)
}
@MainActor @Test func ordinaryProfileHasNoCancelRowButTemporaryAndScheduleOverridesDo() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    model.select("cool-chassis")
    presenter.rebuild(menu)
    #expect(!model.showsCancellation && !menu.items.contains { $0.title.hasPrefix("Cancel") })
    model.activateForever(); presenter.rebuild(menu)
    #expect(model.showsCancellation && menu.items.contains { $0.title == "Cancel Cool Chassis" })
    model.activateForever(); presenter.rebuild(menu)
    #expect(!model.showsCancellation && !menu.items.contains { $0.title.hasPrefix("Cancel") })
    model.activateFor(seconds: 300); presenter.rebuild(menu)
    #expect(model.showsCancellation && menu.items.contains { $0.title == "Cancel Cool Chassis" })
    model.clearActivation(); model.scheduledPeriodID = UUID(); presenter.rebuild(menu)
    #expect(model.showsCancellation && menu.items.contains { $0.title == "Cancel Cool Chassis" })
    model.clearActivation(); model.blockedScheduleID = UUID(); model.select("system", manual: false); presenter.rebuild(menu)
    #expect(model.showsCancellation && menu.items.contains { $0.title == "Resume Schedule" })
}
@Test func unscheduledDaysAreEmptyAndOnlyExplicitSystemSchedulesAppear() {
    let school = WeeklyPeriod(profileID: "school", weekday: 1, startMinute: 510, endMinute: 750)
    #expect(ScheduleOverviewRow.rows(day: 6, periods: [school]).isEmpty)
    #expect(ScheduleOverviewRow.rows(day: 7, periods: [school]).isEmpty)
    let system = WeeklyPeriod(profileID: "system", weekday: 6, startMinute: 600, endMinute: 700)
    #expect(ScheduleOverviewRow.rows(day: 6, periods: [school, system]).map(\.profileID) == ["system"])
    #expect(ScheduleOverviewRow.rows(day: 7, periods: [school, system]).isEmpty)
}
@Test func conditionOverviewIncludesLaunchDurationAndCloseRulesInProfileOrder() {
    var configuration = AutomationConfiguration()
    var launch = ProfileActivationDefault(); launch.launchWhenOpened = true; launch.applicationID = "example.game"; launch.applicationName = "Game"; launch.kind = .application
    var duration = ProfileActivationDefault(); duration.kind = .duration; duration.seconds = 3900
    var process = ProfileActivationDefault(); process.kind = .application; process.applicationID = "example.school"; process.applicationName = "Study"
    configuration.activationDefaults = ["gaming": launch, "max": duration, "school": process, "system-plus": .init()]
    let rows = ProfileConditionOverviewRow.rows(profiles: BuiltInProfiles.all, automation: configuration)
    #expect(rows.map(\.id) == ["max", "gaming", "school"])
    #expect(rows[0].trigger == nil && rows[0].limit == "For 1 hr 5 min")
    #expect(rows[1].trigger == "When Game opens" && rows[1].limit == "Until Game closes")
    #expect(rows[2].trigger == nil && rows[2].limit == "Until Study closes")
    duration.seconds = 45; configuration.activationDefaults["max"] = duration
    #expect(ProfileConditionOverviewRow.rows(profiles: BuiltInProfiles.all, automation: configuration).first { $0.id == "max" }?.limit == "For 45 sec")
    launch.kind = .forever; configuration.activationDefaults["gaming"] = launch
    #expect(ProfileConditionOverviewRow.rows(profiles: BuiltInProfiles.all, automation: configuration).first { $0.id == "gaming" }?.limit == "Until changed")
}
@MainActor private final class SetupPermission { var status: SMAppService.Status = .requiresApproval }
@Test func setupPromptRequiresStableApprovalAndDiscardsTransientUpdateStatus() {
    var gate = HelperApprovalPromptGate()
    for (required, now, expected) in [(false, 0.0, false), (true, 1, false), (true, 2.9, false),
                                      (false, 3, false), (true, 10, false), (true, 12, true), (false, 13, false)] {
        let present = gate.shouldPresent(approvalRequired: required, now: now)
        #expect(present == expected)
    }
}
@MainActor @Test func setupPromptUsesPermissionNotMissingRegistrationAndMenuOpensInstructions() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let permission = SetupPermission()
    permission.status = .notRegistered
    let capabilities = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, capabilities: capabilities,
                         helperAvailable: { permission.status == .enabled }, helperRegistrationStatus: { permission.status })
    #expect(!model.shouldPresentHelperApproval)
    permission.status = .requiresApproval; model.refreshHelperSetup()
    #expect(model.shouldPresentHelperApproval)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    var openedInstructions = false
    presenter.openHelperSetup = { openedInstructions = true }
    presenter.rebuild(menu)
    let row = try #require(menu.items.first { $0.title == "Allow Fan Control…" })
    let action = try #require(row.action)
    #expect(NSApp.sendAction(action, to: row.target, from: row))
    #expect(openedInstructions)
    permission.status = .enabled; model.refreshHelperSetup()
    #expect(!model.shouldPresentHelperApproval && !model.needsHelperSetup)
    presenter.rebuild(menu)
    #expect(!menu.items.contains { $0.title == "Allow Fan Control…" })
}
@MainActor @Test func setupPromptWaitsForStartupAndDoesNotCompleteWhileRegistrationIsPending() async {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let permission = SetupPermission()
    let capabilities = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: true, capabilities: capabilities,
                         helperAvailable: { false }, helperRegistrationStatus: { permission.status })
    defer { model.stop() }
    #expect(model.helperSetupInitializing && !model.shouldPresentHelperApproval && !model.needsHelperSetup)
    #expect(!model.canActivate(BuiltInProfiles.maximum))
    let controller = HelperSetupWindowController(model: model)
    defer { controller.close() }
    #expect(!controller.refreshApproval() && !controller.completed)
    permission.status = .enabled
    for _ in 0..<10 {
        await Task.yield()
        if !model.helperSetupInitializing { break }
    }
    #expect(!model.helperSetupInitializing && !model.shouldPresentHelperApproval)
    #expect(controller.refreshApproval() && controller.completed)
}
@Test func setupInstructionsHaveSeparateOrderedSteps() {
    #expect(HelperSetupInstructions.steps == ["Open System Settings.", "General → Login Items & Extensions", "Background App Activity → enable Fandy."])
}
@MainActor @Test func setupOpensSystemSettingsOnlyWithFreshMissingApproval() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let permission = SetupPermission()
    let capabilities = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, capabilities: capabilities,
                         helperAvailable: { permission.status == .enabled }, helperRegistrationStatus: { permission.status })
    var opens = 0
    model.openHelperSetup(openSettings: { opens += 1 })
    #expect(opens == 1)
    // Approval may arrive after the guide opens but before the Settings action.
    permission.status = .enabled
    model.openHelperSetup(openSettings: { opens += 1 })
    #expect(opens == 1 && !model.needsHelperSetup)
    permission.status = .notRegistered
    model.openHelperSetup(openSettings: { opens += 1 })
    #expect(opens == 1)
}
@MainActor @Test func dedicatedSetupClosesOnApprovalAndNeverRequiresASettingsWindow() {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let permission = SetupPermission()
    let capabilities = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, capabilities: capabilities,
                         helperAvailable: { permission.status == .enabled }, helperRegistrationStatus: { permission.status })
    let controller = HelperSetupWindowController(model: model)
    defer { controller.close() }
    #expect(controller.window?.title == "Set Up Fandy")
    #expect(controller.window?.styleMask.contains(.resizable) == false)
    #expect(model.helperSetupMessage.contains("Background App Activity"))
    #expect(!controller.refreshApproval() && !controller.completed)
    permission.status = .enabled
    #expect(controller.refreshApproval() && controller.completed)
    #expect(controller.window?.isVisible == false && !model.needsHelperSetup)
    #expect(AppPreferences().launchAtLogin)
    #expect((try? JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8)))?.launchAtLogin == true)
}
@MainActor @Test func resumingAnOccurrenceNeverCancelsOrOverwritesTheRememberedDefault() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: { date })
    model.select("cool-chassis")
    var config = model.automation; config.periods = [.init(profileID: "school", weekday: 1, startMinute: 500, endMinute: 750)]
    model.setAutomation(config); for _ in 0..<8 { await model.tick() }
    #expect(model.isSelected("school"))
    model.cancelActivation(); for _ in 0..<8 { await model.tick() }
    #expect(model.isSelected("cool-chassis") && model.showsCancellation)
    #expect(model.cancellationTitle == "Resume Schedule")
    model.cancelActivation(); for _ in 0..<8 { await model.tick() }
    #expect(model.isSelected("school") && model.automation.preferences.defaultProfileID == "cool-chassis")
    config = model.automation; config.periods = []; model.setAutomation(config)
    for _ in 0..<8 { await model.tick() }
    #expect(model.isSelected("cool-chassis") && !model.showsCancellation)
}

@MainActor @Test func approvedFailedHelperShowsRecoveryInsteadOfPermissionAndExportsStructuredFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let capabilities = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
        capabilities: capabilities, helperAvailable: { true }, helperRegistrationStatus: { .enabled })
    model.helperBootstrap = .init(stage: .failed, attempt: 3, failureCode: "smc_open")
    model.helperSetupError = "Bootstrap error retained"
    model.refreshHelperSetup()
    #expect(model.helperSetupError == "Bootstrap error retained")
    #expect(!model.needsHelperSetup && !model.shouldPresentHelperApproval && model.needsHelperAttention)
    let menu = NSMenu(), presenter = StatusMenu(model: model, install: false); presenter.rebuild(menu)
    #expect(!menu.items.contains { $0.title == "Allow Fan Control…" })
    #expect(menu.items.contains { $0.title == "Retry Fan Helper" })
    #expect(menu.items.contains { $0.title == "Export Diagnostics…" })
    let data = try JSONSerialization.jsonObject(with: model.sanitizedDiagnostics()) as! [String: Any]
    #expect(data["bootstrapStage"] as? String == "failed")
    #expect(data["bootstrapAttempt"] as? Int == 3)
    #expect(data["build"] as? String == "24")
}

private actor BootstrapClient: PrivilegedFanClient {
    var applies = 0
    let stage: HelperBootstrapStatus.Stage
    init(stage: HelperBootstrapStatus.Stage) { self.stage = stage }
    func status() -> HelperStatus {
        var value = HelperStatus(automaticVerified: false, observationOnly: true, fault: "Fan helper could not start")
        value.bootstrap = .init(stage: stage, attempt: 3, failureCode: stage == .failed ? "unsupported_metadata" : nil)
        return value
    }
    func apply(_ targets: [FanTarget], generation: UInt64) { applies += 1 }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) { applies += 1 }
    func restoreAutomatic() throws { throw ControlError.restorationUnverified }
}
@MainActor @Test(arguments: [HelperBootstrapStatus.Stage.failed, .initializing, .restoring])
func nonReadyApprovedBackendRemainsObservableWithoutApprovalOrControl(stage: HelperBootstrapStatus.Stage) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = BootstrapClient(stage: stage)
    let capabilities = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, client: client,
        capabilities: capabilities, helperAvailable: { true }, helperRegistrationStatus: { .enabled })
    for _ in 0..<4 { await model.tick() }
    #expect(model.helperBootstrap?.stage == stage && !model.shouldPresentHelperApproval)
    #expect(model.helperHealth != .controlReady && !model.canActivate(BuiltInProfiles.maximum))
    #expect(await client.applies == 0)
    if stage == .failed { #expect(model.needsHelperAttention && model.hardwareError == "Fan helper could not start") }
}
