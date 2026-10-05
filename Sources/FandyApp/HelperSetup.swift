import AppKit
import SwiftUI
import ServiceManagement
import FandyCore

/// Presentation only: never grants helper or hardware authority. A transient
/// approval status during replacement must not flash an unnecessary window.
struct HelperApprovalPromptGate {
    private var requiredSince: Double?
    mutating func shouldPresent(approvalRequired: Bool, now: Double) -> Bool {
        guard approvalRequired else { requiredSince = nil; return false }
        if requiredSince == nil { requiredSince = now }
        return now - (requiredSince ?? now) >= 2
    }
}

extension AppModel {
    var needsHelperSetup: Bool { !simulation && capabilities.canRestore && !helperSetupInitializing && helperSetupStatus != .enabled }
    /// Not registered yet is initialization, not evidence that permission was denied.
    var shouldPresentHelperApproval: Bool { needsHelperSetup && helperSetupStatus == .requiresApproval }
    var helperSetupMessage: String {
        helperSetupError ?? (helperSetupStatus == .requiresApproval
            ? "Allow Fandy under Background App Activity in System Settings to enable fan control."
            : "Enable Fandy’s background helper to use fan profiles.")
    }
    func refreshHelperSetup() {
        let status = helperRegistrationStatus()
        if status != helperSetupStatus { helperSetupStatus = status }
        if status == .enabled { helperSetupError = nil }
    }
    func prepareHelperSetup() {
        refreshHelperSetup()
        // Tests/diagnostics never install a service. Distribution registration
        // retains the Applications-location and signed-client requirements.
        guard !simulation, capabilities.canRestore, helperSetupStatus != .enabled,
              Bundle.main.bundleIdentifier == FandyIdentity.appIdentifier,
              !CommandLine.arguments.contains("--functional-check"),
              (try? HelperDiagnosticAction.parse(CommandLine.arguments)) == nil else { return }
        do { try HelperManager.install(); refreshHelperSetup() }
        catch { helperSetupError = error.localizedDescription }
    }
    func openHelperSetup(openSettings: () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        prepareHelperSetup()
        guard shouldPresentHelperApproval else { return }
        openSettings()
    }
    static func approvalDot() -> NSImage? {
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Fan helper approval needed")?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
        image?.isTemplate = false
        return image
    }
}
struct HelperApprovalNotice: View {
    @Bindable var model: AppModel
    var showButton = true
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(.red).frame(width: 7, height: 7).padding(.top, 4).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.helperSetupMessage).font(.caption).fixedSize(horizontal: false, vertical: true)
                if showButton { Button("Open System Settings…") { model.openHelperSetup() }.controlSize(.small) }
            }
        }.accessibilityIdentifier("helper.approval-needed")
    }
}
