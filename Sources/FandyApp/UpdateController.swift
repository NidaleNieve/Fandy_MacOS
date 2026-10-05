import AppKit
import SwiftUI
import Sparkle
import FandyCore

/// Sparkle owns scheduling, signature checks, downloads and its native update UI.
/// The application owns the safety boundary before replacing its embedded helper.
@MainActor @Observable final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private weak var model: AppModel?
    private var controller: SPUStandardUpdaterController!
    private var appliedPolicy: UpdatePolicy?
    private var preparation: UpdatePreparation!
    private(set) var installationPending = false
    private(set) var status = ""
    private(set) var canCheck = false
    init(model: AppModel) {
        self.model = model
        super.init()
        preparation = UpdatePreparation { [weak model] in
            guard let model else { throw ControlError.helperUnavailable }
            try await model.prepareForUpdate()
        }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        synchronize()
        do { try controller.updater.start() }
        catch { status = "Updates unavailable. Please reinstall the latest release." }
        synchronize()
    }
    func synchronize() {
        guard let model else { return }
        let policy = UpdatePolicy(model.automation.preferences)
        if appliedPolicy != policy {
            controller.updater.updateCheckInterval = policy.interval
            controller.updater.automaticallyDownloadsUpdates = policy.automatic
            controller.updater.automaticallyChecksForUpdates = policy.checksEnabled
            controller.updater.sendsSystemProfile = false
            appliedPolicy = policy
        }
        canCheck = controller.updater.canCheckForUpdates
    }
    func check() {
        guard appliedPolicy?.automatic == false, canCheck else { return }
        controller.checkForUpdates(nil)
    }
    func prepareInstallation() async -> Bool {
        status = "Preparing update…"
        do { try await preparation.prepare(); status = "Ready to install"; return true }
        catch { status = "Update paused. Restore System control and try again."; return false }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        installationPending = true
        status = "Update downloaded. Installs when Fandy quits."
        return false // Retain Sparkle's native two-week reminder and install-on-quit path.
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        installationPending = true
        Task { if await prepareInstallation() { installHandler() } }
        return true
    }
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip { installationPending = false; status = "Update skipped" }
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        installationPending = false
        status = "Update check failed. Try again later."
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error, (error as NSError).code != SUError.noUpdateError.rawValue {
            status = "Update check failed. Try again later."
        } else if !installationPending { status = "Up to date" }
        synchronize()
    }
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
    nonisolated func standardUserDriverWillShowModalAlert() { Task { @MainActor in NSApp.activate(ignoringOtherApps: true) } }
}

struct UpdateSettings: View {
    @Bindable var model: AppModel
    var body: some View {
        Section("Updates") {
            Toggle("Automatic updates", isOn: Binding(get: { model.automation.preferences.automaticUpdates }, set: { value in
                model.setPreferences { $0.automaticUpdates = value }; model.updates?.synchronize()
            }))
            Picker("Check frequency", selection: Binding(get: { model.automation.preferences.updateFrequency }, set: { value in
                model.setPreferences { $0.updateFrequency = value }; model.updates?.synchronize()
            })) { ForEach(UpdateFrequency.allCases) { Text($0.title).tag($0) } }
            .disabled(model.automation.preferences.automaticUpdates)
            Button("Check for Updates…") { model.updates?.check() }
                .disabled(model.automation.preferences.automaticUpdates || model.updates?.canCheck != true)
            if let status = model.updates?.status, !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
