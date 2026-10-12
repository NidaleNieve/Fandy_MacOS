import AppKit
import Foundation
import Security
import ServiceManagement
import Testing
import FandyCore
@testable import FandyApp

@Test func brokenResourceSignatureIsRejectedBeforeHelperRegistration() {
    for status in [OSStatus(-67056), errSecCSUnsigned, errSecCSReqFailed] {
        #expect(throws: HelperInstallationError.invalidSignature) {
            try HelperInstallationPolicy.validate(signatureStatus: status, developerID: false,
                                                  bundleURL: URL(fileURLWithPath: "/Development/Fandy.app"))
        }
    }
}
@Test func validInstalledReleaseAndSignedDevelopmentCopiesRetainTheirLocationPolicy() throws {
    try HelperInstallationPolicy.validate(signatureStatus: errSecSuccess, developerID: true,
                                          bundleURL: URL(fileURLWithPath: "/Applications/Fandy.app"))
    try HelperInstallationPolicy.validate(signatureStatus: errSecSuccess, developerID: false,
                                          bundleURL: URL(fileURLWithPath: "/Development/Fandy.app"))
    #expect(throws: HelperInstallationError.wrongLocation) {
        try HelperInstallationPolicy.validate(signatureStatus: errSecSuccess, developerID: true,
                                              bundleURL: URL(fileURLWithPath: "/Downloads/Fandy.app"))
    }
}
@MainActor @Test func invalidAppCopyIsNotMisreportedAsMissingBackgroundPermission() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    for registration in [SMAppService.Status.enabled, .requiresApproval] {
        let model = AppModel(storeURL: dir.appendingPathComponent("\(registration.rawValue).json"), autoStart: false,
                             capabilities: HardwareCapabilities(model: "Fixture", stage: .restorationQualification, topology: .verified),
                             helperAvailable: { true }, helperRegistrationStatus: { registration })
        model.recordHelperInstallationFailure(HelperInstallationError.invalidSignature)
        #expect(!model.needsHelperSetup && !model.shouldPresentHelperApproval && model.needsHelperAttention)
        #expect(model.helperSetupMessage.contains("Reinstall") && model.helperSetupMessage.contains("Applications"))
        #expect(!model.canActivateCustomFanSpeed && !model.canActivate(BuiltInProfiles.maximum))
        #expect(model.canActivate(BuiltInProfiles.system))
        var opened = false
        model.openHelperSetup { opened = true }
        #expect(!opened)
        let menu = NSMenu(), presenter = StatusMenu(model: model, install: false)
        presenter.rebuild(menu)
        #expect(!menu.items.contains { $0.title == "Allow Fan Control…" })
    }
}

@Test func embeddedHelperIdentityAndSealAreRequiredEvenWhenAppIsValid() {
    for state in [(errSecCSUnsigned, true), (errSecSuccess, false)] {
        #expect(throws: HelperInstallationError.invalidSignature) {
            try HelperInstallationPolicy.validate(signatureStatus: errSecSuccess, developerID: true,
                bundleURL: URL(fileURLWithPath: "/Applications/Fandy.app"),
                helperSignatureStatus: state.0, identitiesMatch: state.1)
        }
    }
}

@MainActor @Test func registrationLifecycleSerializesDifferentOperationsAndRecoversAfterFailure() async throws {
    let lifecycle = HelperLifecycleCoordinator()
    var events: [String] = []
    let first = Task { @MainActor in
        try await lifecycle.run {
            events.append("release-start")
            try await Task.sleep(for: .milliseconds(40))
            events.append("release-end")
            throw ControlError.restorationUnverified
        }
    }
    await Task.yield()
    let second = Task { @MainActor in
        try await lifecycle.run { events.append("register") }
    }
    do { try await first.value; Issue.record("Expected release failure") } catch ControlError.restorationUnverified {}
    try await second.value
    #expect(events == ["release-start", "release-end", "register"])
    #expect(!lifecycle.busy)
}
