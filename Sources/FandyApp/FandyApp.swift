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
                let okay = model.machine.selected.id == "system" && model.machine.state == .system && model.tickCount >= 3 && model.snapshot != nil
                var report: [String: Any] = ["functionalCheck": okay ? "passed" : "failed", "ticks": model.tickCount,
                    "state": model.machine.state.rawValue, "simulation": model.simulation,
                    "observedFanOwnership": model.ownership.rawValue, "helperHealth": model.helperHealth.rawValue,
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let model else { return }
        let status = StatusMenu(model: model)
        status.openProfiles = { [weak self] in self?.showProfiles() }
        status.openSettings = { [weak self] in self?.showSettings() }
        menu = status
    }
    private func window<V: View>(_ title: String, size: NSSize, view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view); window.center(); return window
    }
    func showProfiles() {
        guard let model else { return }
        if profilesWindow == nil { profilesWindow = window("Fandy Profiles", size: NSSize(width: 760, height: 720), view: ProfileEditor(model: model)) }
        profilesWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func showSettings() {
        guard let model else { return }
        if settingsWindow == nil { settingsWindow = window("Fandy Settings", size: NSSize(width: 500, height: 640), view: SettingsView(model: model)) }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.canTerminate { return .terminateNow }
        model.quit(); return .terminateCancel
    }
}
