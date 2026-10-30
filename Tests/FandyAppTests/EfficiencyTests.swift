import Foundation
import Testing
import FandyCore
@testable import FandyApp

@MainActor @Test func unchangedStatusPresentationDoesNotRedrawTheMenuBar() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    var updates = 0
    let menu = StatusMenu(model: model, install: false, onPresentation: { _ in updates += 1 })
    #expect(updates == 1)
    for _ in 0..<60 { menu.updateTitle() }
    #expect(updates == 1)
    model.select("cool-chassis"); menu.updateTitle()
    #expect(updates == 2)
    menu.updateTitle(); #expect(updates == 2)
}

@MainActor @Test func eventDrivenStatusStillRespondsToProfileChangesWithoutAPeriodicTimer() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    var latest: StatusItemPresentation?
    let menu = StatusMenu(model: model, install: false, onPresentation: { latest = $0 })
    model.select("cool-chassis")
    for _ in 0..<50 { if latest?.tooltip.contains("Cool Chassis") == true { break }; await Task.yield() }
    #expect(latest?.tooltip.contains("Cool Chassis") == true)
    _ = menu // Keep the real observation owner alive for the whole check.
}
