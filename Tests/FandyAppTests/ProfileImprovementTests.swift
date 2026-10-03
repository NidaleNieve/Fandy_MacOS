import Foundation
import AppKit
import Testing
import FandyCore
@testable import FandyApp

@MainActor @Test func failedCollectionMutationRetainsUIAndCanRetry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("blocked".utf8).write(to: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let before = model.profiles, selection = model.editorSelection
    model.create(); await model.waitForCollection()
    #expect(model.profiles == before && model.editorSelection == selection)
    #expect(model.saveError != nil)
    try FileManager.default.removeItem(at: root)
    model.save(); await model.waitForCollection()
    #expect(model.profiles.count == 7 && model.saveError == nil)
    #expect(model.machine.selected.id == "system")
}
@MainActor @Test func importIsAtomicNeverActivatesAndRefusesInvalidBatch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.importProfiles(Data("invalid".utf8)); #expect(model.profiles.count == 6)
    model.importProfiles(try ProfileInterchange.encode([BuiltInProfiles.gaming]))
    await model.waitForCollection()
    #expect(model.profiles.count == 7); #expect(model.machine.selected.id == "system")
}
@MainActor @Test func groupedUndoRedoRestoresExactProfileValues() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.editorHistory.groupsByEvent = false
    model.editorSelection = "school"
    let original = try #require(model.edited)
    model.beginEditGroup()
    var next = original; next.floor = 21.25; model.update(next)
    next.floor = 24.5; model.update(next); model.endEditGroup()
    #expect(model.canUndo)
    model.editorHistory.undo(); #expect(model.edited == original)
    #expect(model.canRedo)
    model.editorHistory.redo(); #expect(model.edited == next)
}
@MainActor @Test func diagnosticsExportCannotLeakUserControlledNamesPathsOrMessages() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(storeURL: root.appendingPathComponent("private-user/profiles.json"), autoStart: false, simulation: true)
    model.hardwareError = "/synthetic/secret-person/private-error"
    model.editorSelection = "school"
    var next = try #require(model.edited); next.name = "Personal secret project"; model.update(next)
    let text = String(decoding: try model.sanitizedDiagnostics(), as: UTF8.self)
    #expect(!text.contains("secret-person") && !text.contains("Personal secret") && !text.contains("private-user"))
    #expect(text.contains("monitoring_or_control_error"))
}
@Test func keyboardFineAdjustmentRetainsValidationAndExactPrecision() throws {
    let original = FanCurve(.trackpad, [(25, 10), (30, 40), (40, 100)])
    var draft = CurveDraft(original); draft.select(original.points[1].id)
    let result = draft.nudge(temperature: 0.1, percent: 0.1)
    let moved = try #require(result)
    #expect(moved.points[1].temperature == 30.1 && moved.points[1].percent == 40.1)
    let invalid = draft.nudge(temperature: -5.1)
    #expect(invalid == nil)
}

@MainActor @Test func interruptedGestureHistoryCannotLeakAcrossSelection() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.editorHistory.groupsByEvent = false; model.editorSelection = "school"
    model.beginEditGroup(); model.beginEditGroup()
    var profile = try #require(model.edited); profile.floor = 20; model.update(profile)
    model.editorSelection = "gaming"; model.resetEditorHistory(); model.endEditGroup()
    #expect(model.editorHistory.groupingLevel == 0 && !model.canUndo)
    #expect(model.profiles.first { $0.id == "school" }?.floor == 20)
}

@MainActor @Test func manuallyPolledDiagnosticsObservePowerWithoutStartingAnotherLoop() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let center = NotificationCenter()
    let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, powerCenter: center)
    model.observePower(); model.observePower()
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    for _ in 0..<10 { await Task.yield() }
    #expect(model.powerTransitionCount == 1 && model.tickCount == 0)
    model.stop()
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    for _ in 0..<10 { await Task.yield() }
    #expect(model.powerTransitionCount == 1)
}
