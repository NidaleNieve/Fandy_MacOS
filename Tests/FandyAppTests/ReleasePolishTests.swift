import Foundation
import AppKit
import SwiftUI
import Testing
@testable import FandyApp
@testable import FandyCore

@Test func fanMenuPreferencesDefaultOnAndRoundTrip() throws {
    let old = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
    #expect(old.showFanSpeedBar && old.showFanSpeedNumbers)
    var config = AutomationConfiguration(); config.preferences.showFanSpeedBar = false; config.preferences.showFanSpeedNumbers = false
    let restored = try ConfigurationInterchange.decode(ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: config)))
    #expect(!restored.automation.preferences.showFanSpeedBar && !restored.automation.preferences.showFanSpeedNumbers)
}
@MainActor @Test func manualApplicationConditionWaitsThenExpiresWhenObservedInstanceEnds() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    var catalog: [RunningProcess] = []
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, applicationCatalog: { catalog })
    var rule = ProfileActivationDefault(); rule.kind = .application; rule.applicationID = "example.game"; rule.applicationName = "Game"
    model.setActivationDefault(rule, profileID: "gaming"); model.select("gaming")
    #expect(model.machine.selected.id == "gaming" && model.awaitingApplicationID == rule.applicationID)
    model.expireActivation(); #expect(model.manualIntent != nil)
    catalog = [RunningProcess(pid: -1, launched: Date(), name: "Game", bundleID: rule.applicationID, icon: nil)]
    model.expireActivation()
    // The catalog found an instance that already ended. Fresh process identity
    // rejects it and releases the activation rather than retaining stale control.
    #expect(model.manualIntent == nil && model.awaitingApplicationID == nil && model.machine.selected.id == "system")
}
@MainActor @Test func longCancellationKeepsFullAccessibleTitleInWrappedRow() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.select("max"); model.activateForever()
    var config = model.automation; config.periods = [.init(profileID: "school", weekday: 1, startMinute: 0, endMinute: 1440)]; model.setAutomation(config)
    let menu = NSMenu(); StatusMenu(model: model, install: false).rebuild(menu)
    let title = model.cancellationTitle
    #expect(title.contains("Resume Schedule"))
    let row = try #require(menu.items.first { $0.accessibilityLabel() == title })
    #expect(row.view != nil && row.accessibilityLabel() == title && row.toolTip == title)
    #expect(row.view!.frame.width == MenuLayout.width)
    #expect(menu.size.width <= MenuLayout.maximumMenuWidth)
}
@MainActor @Test func restoredProfileLayoutKeepsItsOriginalNativeSidebarBounds() {
    let outer = ProfileSplitView(sidebar: { Text("Profiles") }, detail: { Text("Editor") }).makeController()
    #expect(outer.splitViewItems[0].minimumThickness == 220)
    #expect(outer.splitViewItems[1].minimumThickness == 660)
    #expect(outer.splitViewItems.allSatisfy { !$0.canCollapse })
    #expect(ProfilesWindow.minimumContentSize == NSSize(width: 960, height: 560))
}
@MainActor @Test func resetDefaultsClearsPortableConfigurationAndReturnsSystem() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.create(); await model.waitForCollection()
    model.setPreferences { $0.showFanSpeedBar = false; $0.launchAtLogin = false; $0.menuSensors = ["role:cpuAverage"] }
    var config = model.automation; config.periods = [.init(profileID: "school", weekday: 1, startMinute: 510, endMinute: 600)]; model.setAutomation(config)
    model.select("max"); model.activateFor(seconds: 300)
    model.resetToDefaults(); await model.waitForCollection()
    #expect(model.profiles == BuiltInProfiles.all && model.automation == AutomationConfiguration())
    #expect(model.machine.selected.id == "system" && model.manualIntent == nil)
    let saved = ProfileStore(url: dir.appendingPathComponent("profiles.json")).load()
    #expect(saved.profiles == BuiltInProfiles.all && saved.automation == AutomationConfiguration())
}

@MainActor @Test func untilChangedPinsInsteadOfCancellingAWaitingApplicationCondition() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, applicationCatalog: { [] })
    var rule = ProfileActivationDefault(); rule.kind = .application; rule.applicationID = "example.game"; rule.applicationName = "Game"
    model.setActivationDefault(rule, profileID: "gaming"); model.select("gaming")
    model.activateForever()
    #expect(model.machine.selected.id == "gaming" && model.awaitingApplicationID == nil)
    #expect(model.manualIntent?.limit == .forever && model.activationDescription == "Manual · until changed")
}

@Test func compactMenuTemperaturesKeepMetadataOutOfVisibleReadings() {
    #expect(MenuTemperatureReadout.compact("CPU Average · estimate") == "CPU Average")
    #expect(MenuTemperatureReadout.temperature("48.2°C · estimate") == "48.2°C")
    #expect(MenuTemperatureReadout.temperature("48°C ≈") == "48°C")
    #expect(MenuTemperatureReadout.temperature("Unavailable on this Mac") == "—")
    #expect(MenuTemperatureReadout.valueWidth == 60)
}
