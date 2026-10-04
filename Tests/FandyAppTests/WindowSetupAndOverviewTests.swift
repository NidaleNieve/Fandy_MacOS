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
        #expect(size.width >= 780 && size.height >= 480)
    }
    window.setContentSize(NSSize(width: 20, height: 10))
    #expect(window.contentRect(forFrameRect: window.frame).size.width >= 780)
    #expect(window.contentRect(forFrameRect: window.frame).size.height >= 480)
    window.setFrame(NSRect(x: 0, y: 0, width: 50, height: 30), display: false)
    #expect(window.contentRect(forFrameRect: window.frame).size.width >= 780)
    #expect(window.contentRect(forFrameRect: window.frame).size.height >= 480)
    window.setFrame(NSRect(x: 0, y: 0, width: 60, height: 25), display: false, animate: false)
    #expect(window.contentRect(forFrameRect: window.frame).size.height >= 480)
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
