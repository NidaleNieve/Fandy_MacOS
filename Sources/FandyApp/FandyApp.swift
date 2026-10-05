import SwiftUI
import AppKit
import FandyCore

@main
struct FandyApp: App {
    @State private var model: AppModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        let diagnostic: HelperDiagnosticAction?
        do { diagnostic = try HelperDiagnosticAction.parse(CommandLine.arguments) }
        catch { FileHandle.standardError.write(Data("Conflicting helper diagnostic actions.\n".utf8)); exit(1) }
        let checking = CommandLine.arguments.contains("--functional-check")
        let model = AppModel(storeURL: checking || diagnostic != nil ? FileManager.default.temporaryDirectory.appendingPathComponent("FandyCheck-\(UUID().uuidString)/profiles.json") : nil, autoStart: diagnostic == nil, simulation: CommandLine.arguments.contains("--simulation"))
        _model = State(initialValue: model)
        delegate.model = model
        if let diagnostic {
            Task { exit(await HelperDiagnostics.run(diagnostic)) }
        }
        if checking {
            Task {
                try? await Task.sleep(for: .seconds(5))
                let okay = model.machine.selected.id == "system" && model.machine.state == .system && model.tickCount >= 3 && model.snapshot != nil && model.hardwareError == nil
                var report: [String: Any] = ["functionalCheck": okay ? "passed" : "failed", "ticks": model.tickCount,
                    "state": model.machine.state.rawValue, "simulation": model.simulation,
                    "observedFanOwnership": model.ownership.rawValue, "monitoringIssuePresent": model.hardwareError != nil, "helperHealth": model.helperHealth.rawValue,
                    "hardwareStage": model.capabilities.stage.rawValue,
                    "physicalWritesEnabled": model.capabilities.canRestore || model.capabilities.canControl,
                    "fanModes": model.snapshot?.fans.map { $0.mode.rawValue } ?? []]
                if let preview = model.preview { report["previewPercent"] = preview.percent; report["previewUsesCandidates"] = preview.usesCandidates }
                if var data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) { data.append(10); FileHandle.standardOutput.write(data) }
                model.quit()
            }
        }
    }
    var body: some Scene {
        Settings { SettingsView(model: model) }

    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var menu: StatusMenu?
    private var profilesWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var helperSetupWindow: HelperSetupWindowController?
    private var helperSetupTask: Task<Void, Never>?
    private var shortcuts: GlobalShortcuts?
    private var shortcutLoop: Task<Void, Never>?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let model else { return }
        let status = StatusMenu(model: model)
        status.openProfiles = { [weak self] in self?.showProfiles() }
        status.openSettings = { [weak self] in self?.showSettings() }
        status.openHelperSetup = { [weak self] in self?.showHelperSetup() }
        menu = status
        guard !CommandLine.arguments.contains("--functional-check"), (try? HelperDiagnosticAction.parse(CommandLine.arguments)) == nil else { return }
        helperSetupTask = Task { [weak self, weak model] in
            // A fixed delay races update-time re-registration. Wait for actual
            // startup completion, then ask only for explicit native approval.
            while model?.helperSetupInitializing == true {
                guard !Task.isCancelled, model?.isQuitting == false else { return }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            var gate = HelperApprovalPromptGate()
            // Native registration status can briefly lag a completed register.
            // Observe explicit approval continuously; enabled exits immediately.
            for _ in 0..<40 {
                guard !Task.isCancelled, let model, !model.isQuitting,
                      !model.simulation, model.capabilities.canRestore else { return }
                model.refreshHelperSetup()
                if !model.helperSetupInitializing && model.helperSetupStatus == .enabled { return }
                if gate.shouldPresent(approvalRequired: model.shouldPresentHelperApproval, now: model.clockNow()) {
                    self?.showHelperSetup(); return
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
        model.updates = UpdateController(model: model)
        let shortcuts = GlobalShortcuts(); self.shortcuts = shortcuts
        shortcuts.invoke = { [weak self, weak model] action in
            if action == "menu" { self?.menu?.toggle() } else { model?.toggleProfile(action) }
        }
        shortcutLoop = Task { [weak model, weak shortcuts] in
            while !Task.isCancelled {
                guard let model, let shortcuts else { return }
                model.shortcutErrors = shortcuts.update(model.automation.preferences.shortcuts)
                model.updates?.synchronize()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    private func window<V: View>(_ title: String, size: NSSize, view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        let controller = NSHostingController(rootView: view); controller.sizingOptions = []
        window.contentViewController = controller; window.center(); return window
    }
    func showProfiles() {
        guard let model else { return }
        if profilesWindow == nil {
            profilesWindow = ProfilesWindow.make(content: ProfileEditor(model: model))
        }
        if let profilesWindow { present(profilesWindow) }
    }
    private func showHelperSetup() {
        guard let model, !model.isQuitting, !model.helperSetupInitializing else { return }
        model.prepareHelperSetup()
        guard model.needsHelperSetup else { helperSetupWindow?.refreshApproval(); return }
        if helperSetupWindow == nil { helperSetupWindow = HelperSetupWindowController(model: model) }
        guard let controller = helperSetupWindow, let window = controller.window else { return }
        present(window); controller.monitorApproval()
    }
    func showSettings() {
        guard let model else { return }
        if settingsWindow == nil { settingsWindow = window("Fandy Settings", size: NSSize(width: 500, height: 640), view: SettingsView(model: model)) }
        if let settingsWindow { present(settingsWindow) }
    }
    private func present(_ window: NSWindow) {
        menu?.item?.menu?.cancelTracking()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil); window.orderFrontRegardless()
        // Menu tracking can otherwise order a window behind the outgoing menu.
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }; NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        }
    }
    func applicationWillTerminate(_ notification: Notification) { helperSetupTask?.cancel(); helperSetupWindow?.close(); shortcutLoop?.cancel(); shortcuts?.stop() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.canTerminate { return .terminateNow }
        model.quit(); return .terminateCancel
    }
}
