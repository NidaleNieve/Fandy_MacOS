import AppKit
import Sparkle

@MainActor final class Driver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { print("offered:\(state.stage.rawValue)"); fflush(stdout); reply(.install) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) { print("no-update"); fflush(stdout); acknowledgement(); NSApp.terminate(nil) }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) { print("error:\((error as NSError).code)"); fflush(stdout); acknowledgement(); exit(2) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { print("download"); fflush(stdout) }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { print("extract"); fflush(stdout) }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { print("ready"); fflush(stdout); reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { print("installed"); fflush(stdout); acknowledgement() }
    func dismissUpdateInstallation() {}
    func showUpdateInFocus() {}
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    let driver = Driver()
    var updater: SPUUpdater!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        if Bundle.main.infoDictionary?["CFBundleVersion"] as? String == "12" { print("relaunched:12"); fflush(stdout); NSApp.terminate(nil); return }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do { try updater.start(); updater.checkForUpdatesInBackground() } catch { print("start-error"); exit(3) }
        DispatchQueue.main.asyncAfter(deadline: .now()+45) { print("timeout"); exit(4) }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        print("pending-on-quit"); fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now()+1) { NSApp.terminate(nil) }
        return false
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        print("rejected:\((error as NSError).code)"); fflush(stdout); exit(2)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { print("quit-boundary"); fflush(stdout); return .terminateNow }
}
let delegate = Delegate()
let app = NSApplication.shared; app.delegate = delegate; app.run()
