import AppKit
import Foundation
import Testing
import FandyCore
@testable import FandyApp

@MainActor @Test func menuVisibilityPersistsUndoesAndDoesNotDeactivateHiddenProfiles() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    let generation = model.machine.generation
    model.editorHistory.groupsByEvent = false
    model.editorHistory.beginUndoGrouping()
    var hidden = try #require(model.profiles.first { $0.id == "cool-chassis" }); hidden.showInMenuBar = false
    model.update(hidden); model.editorHistory.endUndoGrouping()
    #expect(model.machine.generation == generation && model.machine.selected.id == hidden.id)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    model.setPreferences { $0.showActivationTiming = false }; presenter.rebuild(menu)
    #expect(!menu.items.contains { $0.title == "Activate for/until" || $0.title == "Cool Chassis" })
    #expect(menu.items.contains { $0.title == "Custom Fan Speed" })
    model.editorHistory.undo(); presenter.rebuild(menu)
    #expect(menu.items.contains { $0.title == "Cool Chassis" })
    for original in [BuiltInProfiles.system, BuiltInProfiles.maximum] {
        model.editorHistory.beginUndoGrouping()
        var next = original; next.showInMenuBar = false; model.update(next)
        model.editorHistory.endUndoGrouping()
    }
    #expect(model.profiles.filter(\.protected).allSatisfy { !$0.showInMenuBar })
    presenter.rebuild(menu)
    #expect(!menu.items.contains { $0.title == "System" || $0.title == "Max" })
    model.select("system"); for _ in 0..<3 { await model.tick() }
    #expect(model.machine.state == .system)
    await model.prepareForTermination()
    let saved = ProfileStore(url: url).load()
    #expect(saved.issues.isEmpty && !saved.automation.preferences.showActivationTiming)
    #expect(saved.profiles.filter(\.protected).allSatisfy { !$0.showInMenuBar })
}
