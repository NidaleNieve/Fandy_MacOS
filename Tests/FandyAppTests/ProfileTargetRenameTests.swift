import Foundation
import AppKit
import Testing
@testable import FandyCore
@testable import FandyApp

@MainActor @Test func renameRequestsAreDiscoverableAndProtectedProfilesStayProtected() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let coordinator = ProfileSidebar.Coordinator(model: model), table = NSTableView()
    coordinator.table = table; coordinator.update()
    let school = model.profiles.firstIndex { $0.id == "school" }!
    let menu = try #require(coordinator.menu(for: school))
    #expect(menu.items.first?.title == "Rename…" && menu.items.first?.isEnabled == true)
    #expect(coordinator.menu(for: 0)?.items.first?.isEnabled == false)
    #expect(coordinator.menu(for: -1) == nil)
    model.requestRename("system"); #expect(model.renameRequest == nil)
    model.requestRename("school"); #expect(model.renameRequest?.id == "school" && model.editorSelection == "school")
    #expect(!model.renameProfile("system", to: "Other"))
}
@MainActor @Test func renameSupportsUndoWithoutRestartingActiveControl() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.select("school"); for _ in 0..<6 { await model.tick() }
    model.resetEditorHistory(); model.editorHistory.groupsByEvent = false
    let generation = model.machine.generation, state = model.machine.state
    model.editorHistory.beginUndoGrouping(); #expect(model.renameProfile("school", to: "  Quiet Study  ")); model.editorHistory.endUndoGrouping()
    #expect(model.machine.selected.name == "Quiet Study" && model.machine.generation == generation && model.machine.state == state)
    model.editorHistory.undo()
    #expect(model.machine.selected.name == "Silent" && model.machine.generation == generation)
    #expect(!model.renameProfile("school", to: "   "))
    #expect(model.profiles.first { $0.id == "school" }?.name == "Silent")
}
@MainActor @Test func profileTemperatureTargetIsUndoableAndInvalidDraftRetainsSafeState() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.editorSelection = "school"; model.editorHistory.groupsByEvent = false
    var profile = try #require(model.edited)
    model.editorHistory.beginUndoGrouping(); profile.targetTemperature = .init(input: .trackpad, celsius: 29); model.update(profile); model.editorHistory.endUndoGrouping()
    #expect(model.edited?.targetTemperature == profile.targetTemperature)
    var invalid = profile; invalid.targetTemperature?.celsius = .nan; model.update(invalid)
    #expect(model.edited == profile && model.draftError != nil)
    model.editorHistory.undo(); #expect(model.edited?.targetTemperature == nil)
    model.editorHistory.redo(); #expect(model.edited?.targetTemperature == profile.targetTemperature)
}
