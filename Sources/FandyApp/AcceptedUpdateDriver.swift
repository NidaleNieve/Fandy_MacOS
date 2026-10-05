import AppKit
import Sparkle

/// Retain Sparkle's native offer and progress UI. An accepted download is already
/// consent to install; bypass only the redundant ready-to-install confirmation.
@MainActor class AcceptedUpdateDriver: SPUStandardUserDriver {
    var acceptedInstallation = false
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if acceptedInstallation { reply(.install) }
        else { super.showReady(toInstallAndRelaunch: reply) }
    }
    override func dismissUpdateInstallation() {
        acceptedInstallation = false
        super.dismissUpdateInstallation()
    }
}
