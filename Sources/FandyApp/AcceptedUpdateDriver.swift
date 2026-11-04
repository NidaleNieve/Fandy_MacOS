import AppKit
import Sparkle

/// Keep Sparkle's offer and progress UI; an accepted update needs no second confirmation.
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
