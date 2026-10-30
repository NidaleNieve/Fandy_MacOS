import AppKit
import SwiftUI
import ServiceManagement
import FandyCore
import UniformTypeIdentifiers

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
    var needsHelperSetup: Bool { !simulation && helperInstallationSupported && !helperSetupInitializing && helperInstallationIssue == nil && helperSetupStatus == .requiresApproval }
    var needsHelperAttention: Bool {
        !simulation && helperInstallationSupported && !helperSetupInitializing &&
        (helperInstallationIssue != nil || needsHelperSetup || helperSetupStatus != .enabled || (helperHealth == .unavailable && (helperDiagnostic?.stalled == true || (helperBootstrap?.stage != .initializing && helperBootstrap?.stage != .restoring))) || (helperHealth == .fault && helperConnectionFailureCode != nil) || helperBootstrap?.stage == .failed)
    }
    /// Not registered yet is initialization, not evidence that permission was denied.
    var shouldPresentHelperApproval: Bool { needsHelperSetup && helperSetupStatus == .requiresApproval }
    var helperSetupMessage: String {
        helperSetupError ?? helperFailure?.localizedDescription ?? (helperDiagnostic?.stalled == true ? "Fan hardware work is taking longer than expected. Export diagnostics." : nil) ?? (shouldPresentHelperApproval
            ? "Allow Fandy under Background App Activity in System Settings to enable fan control."
            : "Fan helper could not start")
    }
    func recordHelperInstallationFailure(_ error: HelperInstallationError) {
        helperInstallationIssue = error.localizedDescription
        helperSetupError = error.localizedDescription
        helperConnectionFailureCode = "invalid_app_installation"
    }
    func refreshHelperSetup() {
        let status = autoreleasepool { helperRegistrationStatus() }
        if status != helperSetupStatus { helperSetupStatus = status }
    }
    func prepareHelperSetup() {
        refreshHelperSetup()
        // Tests/diagnostics never install a service. Distribution registration
        // retains the Applications-location and signed-client requirements.
        guard !simulation, helperInstallationSupported, helperSetupStatus != .enabled,
              Bundle.main.bundleIdentifier == FandyIdentity.appIdentifier,
              !CommandLine.arguments.contains("--functional-check"),
              (try? HelperDiagnosticAction.parse(CommandLine.arguments)) == nil else { return }
        do { try HelperManager.install(); refreshHelperSetup() }
        catch {
            if let installation = error as? HelperInstallationError { recordHelperInstallationFailure(installation) }
            else { helperSetupError = error.localizedDescription }
        }
    }
    func openHelperSetup(openSettings: () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        prepareHelperSetup()
        guard shouldPresentHelperApproval else { return }
        openSettings()
    }
    func exportDiagnostics() {
        let panel = ExportSavePanel.make(filename: "Fandy Diagnostics.json")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let bundleURL = Bundle.main.bundleURL
                self.installationObservation = await Task.detached { InstallationDiagnostics.collect(bundleURL: bundleURL) }.value
                do { try self.sanitizedDiagnostics().write(to: url, options: .atomic) }
                catch { self.draftError = "Diagnostics could not be exported." }
            }
        }
    }
    func retryFanHelper() {
        guard !isQuitting, !helperSetupInitializing, !simulation else { return }
        Task { await retryApprovedHelper() }
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
                if showButton {
                    if model.shouldPresentHelperApproval { Button("Open System Settings…") { model.openHelperSetup() }.controlSize(.small) }
                    else {
                        HStack { Button("Retry") { model.retryFanHelper() }; Button("Export Diagnostics…") { model.exportDiagnostics() } }.controlSize(.small)
                    }
                }
            }
        }.accessibilityIdentifier("helper.approval-needed")
    }
}
