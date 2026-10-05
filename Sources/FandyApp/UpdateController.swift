import AppKit
import SwiftUI
import Sparkle
import FandyCore

/// Sparkle owns scheduling, signature checks, downloads and its native update UI.
/// The application owns the safety boundary before replacing its embedded helper.
@MainActor @Observable final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private weak var model: AppModel?
    private var updater: SPUUpdater!
    private var driver: AcceptedUpdateDriver!
    private var installDownloaded: (() -> Void)?
    private var reminderAt: Date?
    private var installingNow = false
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
        driver = AcceptedUpdateDriver(hostBundle: .main, delegate: self)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        synchronize()
        do { try updater.start() }
        catch { status = "Updates unavailable. Please reinstall the latest release." }
        synchronize()
    }
    func synchronize() {
        guard let model else { return }
        let policy = UpdatePolicy(model.automation.preferences)
        if appliedPolicy != policy {
            updater.updateCheckInterval = policy.interval
            updater.automaticallyDownloadsUpdates = policy.automatic
            updater.automaticallyChecksForUpdates = policy.checksEnabled
            updater.sendsSystemProfile = false
            appliedPolicy = policy
        }
        canCheck = (updater.canCheckForUpdates || installationPending) && !model.preparingUpdate && !installingNow
        if policy.automatic, let reminderAt, Date() >= reminderAt, canCheck {
            self.reminderAt = Date().addingTimeInterval(UpdatePolicy.reminderInterval)
            presentPendingUpdate()
        }
    }
    func check() {
        guard canCheck, model?.preparingUpdate != true else { return }
        if installationPending { presentPendingUpdate() } else { updater.checkForUpdates() }
    }
    func prepareInstallation() async -> Bool {
        status = "Preparing update…"
        do { try await preparation.prepare(); status = "Ready to install"; return true }
        catch { status = "Update paused. Restore System control and try again."; return false }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        installationPending = true
        installDownloaded = immediateInstallationBlock
        reminderAt = Date().addingTimeInterval(UpdatePolicy.reminderInterval)
        status = "Update downloaded. Ready to install."
        return true // Retain the supported install callback; Settings owns the staged prompt/reminder.
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        installationPending = true
        Task { if await prepareInstallation() { installHandler() } }
        return true
    }
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .install { driver.acceptedInstallation = true }
        if choice == .skip { clearPending(); status = "Update skipped" }
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        clearPending()
        status = "Update check failed. Try again later."
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error, (error as NSError).code != SUError.noUpdateError.rawValue {
            status = "Update check failed. Try again later."
        } else if !installationPending { status = "Up to date" }
        synchronize()
    }
    private func presentPendingUpdate() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "A Fandy update is ready to install"
        alert.informativeText = "Install the downloaded update and restart Fandy now?"
        alert.addButton(withTitle: "Install Update"); alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { installNow() }
    }
    func installNow() {
        guard let installDownloaded, !installingNow, model?.preparingUpdate != true else { return }
        installingNow = true
        Task {
            defer { installingNow = false }
            if await prepareInstallation() { installDownloaded() }
        }
    }
    private func clearPending() {
        installationPending = false; installDownloaded = nil; reminderAt = nil; driver.acceptedInstallation = false
    }
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
    nonisolated func standardUserDriverWillShowModalAlert() { Task { @MainActor in NSApp.activate(ignoringOtherApps: true) } }
}

struct UpdateSettings: View {
    @Bindable var model: AppModel
    var body: some View {
        Section("Updates") {
            LabeledContent("Version", value: FandyBuild.version).accessibilityIdentifier("settings.updateVersion")
            Toggle("Automatic updates", isOn: Binding(get: { model.automation.preferences.automaticUpdates }, set: { value in
                model.setPreferences { $0.automaticUpdates = value }; model.updates?.synchronize()
            }))
            Picker("Check frequency", selection: Binding(get: { model.automation.preferences.updateFrequency }, set: { value in
                model.setPreferences { $0.updateFrequency = value }; model.updates?.synchronize()
            })) { ForEach(UpdateFrequency.allCases) { Text($0.title).tag($0) } }
            .disabled(!model.automation.preferences.automaticUpdates)
            Button("Check for Updates…") { model.updates?.check() }
                .disabled(model.updates?.canCheck != true)
            if model.updates?.installationPending == true {
                Button("Install Update") { model.updates?.installNow() }.disabled(model.preparingUpdate)
            }
            if let status = model.updates?.status, !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
