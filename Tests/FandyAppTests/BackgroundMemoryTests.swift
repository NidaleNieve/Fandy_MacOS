import AppKit
import Foundation
import Testing
import SwiftUI
import FandyCore
@testable import FandyApp

@MainActor @Test func closedMenuReleasesEmbeddedViewsWithoutLosingNativeSelectionActions() async throws {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    presenter.menuWillOpen(menu)
    let selection = try #require(menu.items.first { $0.title == "Cool Chassis" })
    weak var readout = menu.items.compactMap(\.view).last
    #expect(readout != nil)
    presenter.menuDidClose(menu)
    // AppKit may deliver a menu action after menuDidClose. Cleanup must not
    // invalidate that action, even when the menu's view tree is already gone.
    for _ in 0..<20 { await Task.yield() }
    #expect(menu.numberOfItems == 0)
    #expect(readout == nil)
    #expect(NSApp.sendAction(try #require(selection.action), to: selection.target, from: selection))
    #expect(model.menuSelectionID == "cool-chassis")
    presenter.menuWillOpen(menu)
    #expect(menu.items.first { $0.title == "Cool Chassis" }?.state == .on)
}

@MainActor @Test func closedWindowReleasesItsControllerAndReopensWithoutLosingProfileChangesOrGeometry() async throws {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.editorSelection = "cool-chassis"
    var profile = try #require(model.edited); let oldFloor = profile.floor
    profile.floor = 17; model.update(profile)
    let window = ProfilesWindow.make(content: EmptyView())
    let lifecycle = WindowContentLifecycle(window: window) { ProfileHostingController(rootView: ProfileEditor(model: model)) }
    weak var controller: NSViewController?
    var frame = window.frame
    autoreleasepool {
        lifecycle.prepare(); controller = window.contentViewController
        window.setContentSize(NSSize(width: 1080, height: 760)); frame = window.frame
        window.close()
    }
    for _ in 0..<20 { await Task.yield() }
    #expect(window.contentViewController == nil && controller == nil)
    #expect(model.edited?.floor == 17 && model.canUndo)
    lifecycle.prepare()
    #expect(window.contentViewController != nil && window.frame == frame)
    #expect(model.editorSelection == "cool-chassis" && model.edited?.floor == 17)
    model.editorHistory.undo()
    #expect(model.edited?.floor == oldFloor)
}

@MainActor @Test func dormantEditorPreservesUnsubmittedCurveDraftAndRejectsItAfterAnExternalCurveChange() throws {
    let state = EditorPresentationState()
    let curve = BuiltInProfiles.chip
    var draft = CurveDraft(curve); draft.select(curve.points.first?.id)
    draft.temperatureText = "unfinished"; draft.percentText = "43"
    state.saveDraft(draft, for: "cool-chassis:chip", base: curve)
    state.tab = .schedule; state.chipExpanded = false
    let resumed = state.draft(for: "cool-chassis:chip", curve: curve)
    #expect(resumed.temperatureText == "unfinished" && resumed.percentText == "43")
    #expect(state.tab == .schedule && !state.chipExpanded)
    var changed = curve; changed.points[0].percent = 1
    #expect(state.draft(for: "cool-chassis:chip", curve: changed).temperatureText.isEmpty)
}

@MainActor @Test func staleMenuCleanupCannotEraseAReopenedMenu() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    presenter.menuWillOpen(menu); presenter.menuDidClose(menu); presenter.menuWillOpen(menu)
    for _ in 0..<20 { await Task.yield() }
    #expect(presenter.isOpen && menu.numberOfItems > 0)
}

@MainActor @Test func closedSetupWindowReleasesItsHostingGraph() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let controller = HelperSetupWindowController(model: model)
    #expect(controller.window?.contentViewController != nil)
    controller.close()
    #expect(controller.window?.contentViewController == nil && controller.window?.contentView == nil)
}

@MainActor @Test func closedUIReclaimsOnlyFreedAllocatorPagesAndCoalescesRepeatedClosures() async {
    var releases = 0
    let reclaimer = BackgroundMemoryReclaimer(pause: { await Task.yield() }, release: { releases += 1 })
    for _ in 0..<20 { reclaimer.schedule() }
    for _ in 0..<20 { await Task.yield() }
    #expect(releases == 1)
    reclaimer.schedule()
    for _ in 0..<20 { await Task.yield() }
    #expect(releases == 2)
}

@MainActor @Test func closingEditorReleasesNestedSplitControllersAndTheirHostingGraphs() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    final class WeakController { weak var value: NSViewController?; init(_ value: NSViewController) { self.value = value } }
    var watched: [WeakController] = []
    let window = ProfilesWindow.make(content: EmptyView())
    let lifecycle = WindowContentLifecycle(window: window) { ProfileHostingController(rootView: ProfileEditor(model: model)) }
    autoreleasepool {
        lifecycle.prepare(); window.contentView?.layoutSubtreeIfNeeded()
        func collect(_ controller: NSViewController) {
            watched.append(WeakController(controller))
            for child in controller.children { collect(child) }
        }
        if let controller = window.contentViewController { collect(controller) }
        window.close()
    }
    for _ in 0..<40 { await Task.yield() }
    #expect(!watched.isEmpty && watched.allSatisfy { $0.value == nil })
}

@MainActor @Test func unusedHoverControlsAllocateOnlyWhenTheirSubmenuOpensAndNeverCloseTheRoot() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let menu = NSMenu(), presenter = StatusMenu(model: model, install: false)
    presenter.menuWillOpen(menu)
    let timing = try #require(menu.items.first { $0.title == "Activate for/until" }?.submenu)
    for title in ["Other Time/Until", "While App Is Running"] {
        let child = try #require(timing.items.first { $0.title == title }?.submenu)
        #expect(child.items.allSatisfy { $0.view == nil })
        presenter.menuWillOpen(child)
        #expect(child.items.first?.view != nil && presenter.isOpen)
        presenter.menuDidClose(child)
        #expect(presenter.isOpen && menu.numberOfItems > 0)
    }
}

@MainActor @Test func nativeReadoutPreservesFanAndTemperaturePreferencesWithoutAHostingGraph() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, clock: { 1 })
    await model.tick()
    model.setPreferences { $0.menuSensors = ["role:cpuAverage"] }
    let readout = NativeFanMenuStatus(model: model)
    #expect(readout.readingText.contains("RPM") && readout.readingText.contains("%"))
    #expect(readout.frame.width == MenuLayout.width && readout.frame.height > 0)
    model.setPreferences { $0.showFanSpeedBar = false; $0.showFanSpeedNumbers = false }
    for _ in 0..<20 { await Task.yield() }
    #expect(!readout.readingText.contains("RPM") && !readout.readingText.contains("%"))
    #expect(readout.readingText.contains(model.sensorMenu.title(for: "role:cpuAverage")))
}

@MainActor @Test func nativeLaunchRetainsStandardWindowAndTextEditingCommands() throws {
    let delegate = AppDelegate(), root = ApplicationMenu.make(target: delegate)
    let app = try #require(root.items.first?.submenu)
    #expect(app.items.contains { $0.keyEquivalent == "," && $0.target === delegate })
    #expect(app.items.contains { $0.keyEquivalent == "q" && $0.action == #selector(NSApplication.terminate(_:)) })
    let edit = try #require(root.items.first { $0.title == "Edit" }?.submenu)
    for key in ["z", "x", "c", "v", "a"] { #expect(edit.items.contains { $0.keyEquivalent == key && $0.target == nil }) }
}

@MainActor @Test func closingWindowPreservesUserResizedSidebarInsteadOfResettingIt() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let lifecycle = WindowContentLifecycle(window: window) {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.addSplitViewItem(NSSplitViewItem(viewController: NSViewController()))
        controller.addSplitViewItem(NSSplitViewItem(viewController: NSViewController()))
        return controller
    }
    lifecycle.prepare()
    (window.contentViewController as? NSSplitViewController)?.splitView.setPosition(290, ofDividerAt: 0)
    let width = (window.contentViewController as? NSSplitViewController)?.splitView.subviews.first?.frame.width
    window.close(); lifecycle.prepare()
    #expect((window.contentViewController as? NSSplitViewController)?.splitView.subviews.first?.frame.width == width)
    window.close()
}

@MainActor @Test func nativeProfileWindowUsesTheExistingProfileUndoHistory() {
    let window = ProfilesWindow.make(content: EmptyView()), history = UndoManager()
    window.profileUndoManager = history
    #expect(window.undoManager === history)
    window.close()
}
