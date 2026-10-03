import Foundation
import AppKit
import Testing
@testable import FandyCore
@testable import FandyApp

@MainActor @Test func preferencesNeverEnterProfileHistoryAndSurviveUndoRedo() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.editorHistory.groupsByEvent = false
    model.setPreferences { $0.use24HourTime = false }
    #expect(!model.canUndo)
    model.editorHistory.beginUndoGrouping(); model.create(); await model.waitForCollection(); model.editorHistory.endUndoGrouping()
    let created = model.editorSelection
    model.setPreferences { $0.launchAtLogin = false; $0.menuSensors = ["role:cpuAverage"] }
    let settings = model.automation.preferences
    model.editorHistory.undo()
    #expect(!model.profiles.contains { $0.id == created })
    #expect(model.automation.preferences == settings)
    model.editorHistory.redo()
    #expect(model.profiles.contains { $0.id == created })
    #expect(model.automation.preferences == settings)
    model.editorHistory.beginUndoGrouping()
    var duration = ProfileActivationDefault(); duration.kind = .duration; duration.seconds = 300
    model.setActivationDefault(duration, profileID: created)
    model.editorHistory.endUndoGrouping()
    model.setPreferences { $0.showHelperProcesses = true }
    model.editorHistory.undo()
    #expect(model.automation.activationDefaults[created] == nil)
    #expect(model.automation.preferences.showHelperProcesses)
}

@MainActor @Test func activationAvailabilityRenderingDoesNotEnumerateProcesses() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    var queries = 0
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, applicationCatalog: { queries += 1; return [] }, clock: { 10 })
    var rule = ProfileActivationDefault(); rule.kind = .application; rule.applicationID = "example.game"; rule.applicationName = "Game"
    model.setActivationDefault(rule, profileID: "gaming")
    let initial = queries
    for _ in 0..<1000 { #expect(model.activationDefaultUnavailableReason(BuiltInProfiles.gaming) != nil) }
    #expect(queries == initial)
    model.refreshApplicationAvailability(); model.refreshApplicationAvailability()
    #expect(queries == initial)
    model.select("gaming")
    #expect(queries == initial + 1 && model.machine.selected.id == "system")
}

@MainActor @Test func nativeMenuUsesDirectPickersAndCompactReadouts() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    presenter.rebuild(menu)
    let timing = try #require(menu.items.first { $0.title == "Activate for/until" }?.submenu)
    for title in ["Other Time/Until…", "While App Is Running…"] {
        let row = try #require(timing.items.first { $0.title == title })
        #expect(row.submenu == nil && row.action != nil && row.view == nil)
    }
    #expect(menu.items.filter { $0.view != nil }.count == 1)
    let status = try #require(menu.items.compactMap(\.view).first)
    #expect(status.frame.width == MenuLayout.width && status.frame.height < 65)
    #expect(timing.items.compactMap(\.submenu).flatMap(\.items).allSatisfy { $0.view == nil })
    presenter.menuWillOpen(menu); #expect(presenter.isOpen)
    presenter.menuDidClose(menu); #expect(!presenter.isOpen)
    let wide = BoundedMenuAction(title: String(repeating: "W", count: 64))
    #expect(wide.frame.width == MenuLayout.width && wide.frame.height > 24)
}

@MainActor @Test func nativeSidebarSelectionAndActivationAreSeparateAndImmediate() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let coordinator = ProfileSidebar.Coordinator(model: model), table = NSTableView()
    coordinator.table = table; table.dataSource = coordinator; table.delegate = coordinator; coordinator.update()
    let index = model.profiles.firstIndex { $0.id == "gaming" }!
    table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    coordinator.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: table))
    #expect(model.editorSelection == "gaming" && model.machine.selected.id == "system")
    coordinator.activateRow(index)
    #expect(model.menuSelectionID == "gaming")
    coordinator.activateRow(-1); coordinator.activateRow(1000)
    #expect(model.menuSelectionID == "gaming")
}

@MainActor @Test func directCurveSecondaryActionRespectsDisabledState() {
    let surface = CurveContextSurface.Surface()
    var points: [CGPoint] = []
    surface.action = { point in .init(enabled: point.x > 0, perform: { points.append(point) }) }
    surface.apply(at: CGPoint(x: 5, y: 10))
    surface.apply(at: .zero)
    surface.enabled = false; surface.apply(at: CGPoint(x: 20, y: 30))
    #expect(points == [CGPoint(x: 5, y: 10)])
}

@Test func retiredMenuClockIsIgnoredOnImportAndNeverExported() throws {
    let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"showClock":true,"use24HourTime":false}"#.utf8))
    #expect(!preferences.use24HourTime)
    let exported = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as! [String: Any]
    #expect(exported["showClock"] == nil)
}
