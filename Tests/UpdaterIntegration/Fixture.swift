import AppKit
import Sparkle

@MainActor final class Driver: AcceptedUpdateDriver {
    override func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)) }
    override func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { acceptedInstallation = true; print("offered:\(state.stage.rawValue)"); fflush(stdout); reply(.install) }
    override func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    override func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    override func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) { print("no-update"); fflush(stdout); acknowledgement(); NSApp.terminate(nil) }
    override func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) { print("error:\((error as NSError).code)"); fflush(stdout); acknowledgement(); exit(2) }
    override func showDownloadInitiated(cancellation: @escaping () -> Void) { print("download"); fflush(stdout) }
    override func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    override func showDownloadDidReceiveData(ofLength length: UInt64) {}
    override func showDownloadDidStartExtractingUpdate() { print("extract"); fflush(stdout) }
    override func showExtractionReceivedProgress(_ progress: Double) {}
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { print("ready-without-second-confirmation"); fflush(stdout); super.showReady(toInstallAndRelaunch: reply) }
    override func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    override func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { print("installed"); fflush(stdout); acknowledgement() }
    override func dismissUpdateInstallation() {}
    override func showUpdateInFocus() {}
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    let driver = Driver(hostBundle: .main, delegate: nil)
    var updater: SPUUpdater!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        if Bundle.main.infoDictionary?["CFBundleVersion"] as? String == "12" { print("relaunched:12"); fflush(stdout); NSApp.terminate(nil); return }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do { try updater.start(); if Bundle.main.infoDictionary?["FandyFixtureManualCheck"] as? Bool == true { updater.checkForUpdates() } else { updater.checkForUpdatesInBackground() } } catch { print("start-error"); exit(3) }
        DispatchQueue.main.asyncAfter(deadline: .now()+45) { print("timeout"); exit(4) }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        print("pending-on-quit"); fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            if Bundle.main.infoDictionary?["FandyFixtureInstallPending"] as? Bool == true {
                print("install-staged-without-prompt"); fflush(stdout)
                immediateInstallationBlock()
            } else { NSApp.terminate(nil) }
        }
        return Bundle.main.infoDictionary?["FandyFixtureInstallPending"] as? Bool == true
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        print("rejected:\((error as NSError).code)"); fflush(stdout); exit(2)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { print("quit-boundary"); fflush(stdout); return .terminateNow }
}
@main struct FixtureMain {
    @MainActor static func main() {
        let delegate = Delegate()
        let app = NSApplication.shared; app.delegate = delegate; app.run()
    }
}
