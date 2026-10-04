import AppKit
import SwiftUI

/// Setup is independent of Settings and never blocks the controller's main actor.
@MainActor final class HelperSetupWindowController: NSWindowController, NSWindowDelegate {
    let model: AppModel
    private(set) var completed = false
    private var monitor: Task<Void, Never>?
    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: 400, height: 200)),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Set Up Fandy"; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = ProfileHostingController(rootView: HelperSetupView(model: model, later: { [weak self] in self?.close() }))
        window.setContentSize(NSSize(width: 400, height: 200)); window.center()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @discardableResult func refreshApproval() -> Bool {
        model.refreshHelperSetup()
        if !model.needsHelperSetup { completed = true; close(); return true }
        return false
    }
    func monitorApproval() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.refreshApproval() else { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    override func close() { monitor?.cancel(); monitor = nil; super.close() }
    func windowWillClose(_ notification: Notification) { monitor?.cancel(); monitor = nil }
}
private struct HelperSetupView: View {
    @Bindable var model: AppModel
    let later: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Allow fan control", systemImage: "fan").font(.headline)
            Text("System Settings → General → Login Items & Extensions → Background App Activity → enable Fandy.")
                .fixedSize(horizontal: false, vertical: true)
            if let error = model.helperSetupError { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
            HStack {
                Button("Later", action: later).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open System Settings…") { model.openHelperSetup() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 400, height: 200)
    }
}
