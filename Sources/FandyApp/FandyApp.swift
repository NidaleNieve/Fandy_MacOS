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
        MenuBarExtra("Fandy", systemImage: "fan") {
            ForEach(model.profiles) { profile in
                Button { model.select(profile.id) } label: {
                    if model.isSelected(profile.id) { Label(profile.name, systemImage: "checkmark") }
                    else { Text(profile.name) }
                }.disabled(!model.canActivate(profile)).accessibilityIdentifier("profile.\(profile.id)")
            }
            Divider()
            Text(model.statusText).font(.caption)
            if let fault = model.machine.fault { Text(fault).font(.caption) }
            Divider()
            OpenEditorButton()
            SettingsLink { Text("Settings…") }
            Button("Quit") { model.quit() }.keyboardShortcut("q")
        }.menuBarExtraStyle(.menu)
        Window("Fandy Profiles", id: "profiles") {
            ProfileEditor(model: model)
                .task { delegate.model = model; model.start() }
        }.defaultSize(width: 760, height: 660).defaultLaunchBehavior(.suppressed)
        Settings { SettingsView(model: model).task { delegate.model = model; model.start() } }
    }
}
struct OpenEditorButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Edit Profiles…") { openWindow(id: "profiles"); NSApp.activate(ignoringOtherApps: true) } }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.canTerminate { return .terminateNow }
        model.quit(); return .terminateCancel
    }
}
