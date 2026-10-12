import Foundation
import Security
import ServiceManagement
import FandyCore
import FandyHardware

@MainActor enum HelperManager {
    private static let lifecycle = HelperLifecycleCoordinator()
    static var service:SMAppService { .daemon(plistName:FandyIdentity.launchDaemonPlist) }
    static var installed:Bool { service.status == .enabled }
    private static var legacyService: SMAppService { .daemon(plistName: FandyIdentity.legacyLaunchDaemonPlist) }
    /// Older development registrations retain validation category 3 after an
    /// upgrade to Developer ID (category 6), even across unregister/register.
    /// Remove that registration before creating the distribution service; the
    /// XPC name, helper signing identity and caller authentication stay fixed.
    static func migrateLegacyService(client: FanXPCClient) async throws {
        try await lifecycle.run { try await migrateLegacyNative(client: client) }
    }
    private static func migrateLegacyNative(client: FanXPCClient) async throws {
        try validateCurrentInstallation()
        guard legacyService.status == .enabled || legacyService.status == .requiresApproval else { return }
        if legacyService.status == .enabled {
            do { try await client.restoreAutomatic() }
            catch let failure as HelperFailure where failure.kind == .serviceUnavailable { /* Dead legacy job: replacement startup must verify release. */ }
            catch ControlError.helperUnavailable { /* Dead legacy job: replacement startup must verify release. */ }
        }
        try await unregister(service: legacyService)
        client.disconnectForRecoveryTest()
    }
    static func install() throws { try lifecycle.perform { try installNative() } }
    private static func installNative() throws {
        guard legacyService.status != .enabled && legacyService.status != .requiresApproval else { throw ControlError.helperUnavailable }
        guard DeviceRegistry.canInstallHelper(identity: .current) else { throw ControlError.hardwareUnqualified }
        try validateCurrentInstallation()
        switch service.status {
        case .notRegistered, .notFound: try service.register()
        case .enabled, .requiresApproval: break
        @unknown default: throw ControlError.helperUnavailable
        }
    }
    static func installObservation() throws {
        // This path must stop working when a future build gains any physical write capability.
        guard !DeviceRegistry.current.capabilities.canRestore, !DeviceRegistry.current.capabilities.canControl else { throw ControlError.unauthorized }
        try validateCurrentInstallation()
        switch service.status {
        case .notRegistered, .notFound: try service.register()
        case .enabled, .requiresApproval: break
        @unknown default: throw ControlError.helperUnavailable
        }
    }
    static func uninstallObservation(client: FanXPCClient) async throws {
        guard !DeviceRegistry.current.capabilities.canRestore, !DeviceRegistry.current.capabilities.canControl else { throw ControlError.unauthorized }
        if service.status == .enabled {
            let status = try await client.status()
            guard status.observationOnly, !status.manualQualified else { throw ControlError.unauthorized }
        }
        if service.status != .notRegistered { try await unregisterService() }
    }
    static func uninstall(client:FanXPCClient) async throws {
        try await lifecycle.run {
            try await remove(status: service.status, restore: { try await client.restoreAutomatic() },
                unregister: { try await unregister(service: service) })
        }
    }
    /// Approval and availability are separate; a live registration requires handback.
    static func remove(status: SMAppService.Status, restore: () async throws -> Void,
        unregister: () async throws -> Void) async throws {
        switch status {
        case .enabled: try await restore(); try await unregister()
        case .requiresApproval: try await unregister()
        case .notRegistered, .notFound: return
        @unknown default: throw ControlError.helperUnavailable
        }
    }
    static func unregisterService() async throws { try await lifecycle.run { try await unregister(service: service) } }
    /// One serialized replacement, with handback before removal of a reachable controller.
    static func replace(client: FanXPCClient, allowUnavailable: Bool = false, bootstrapFailed: Bool = false) async throws {
        try await lifecycle.run {
            try validateCurrentInstallation()
            if service.status == .enabled {
                do { try await client.restoreAutomatic() }
                catch let failure as HelperFailure where allowUnavailable && failure.kind == .serviceUnavailable { }
                catch ControlError.helperUnavailable where allowUnavailable { }
                catch { guard bootstrapFailed else { throw error } }
                try await unregister(service: service)
            }
            client.disconnectForRecoveryTest()
            try installNative()
        }
    }
    private static func unregister(service: SMAppService) async throws {
        // Bridge the documented completion API on the main actor. macOS 15's SDK
        // does not mark SMAppService Sendable, so its actor-owned wrapper must not
        // be passed to the imported nonisolated async overload.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            service.unregister { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
        // Completion can precede publication of the new status. Do not treat a
        // stale enabled observation as a successfully registered replacement.
        for _ in 0..<50 {
            if service.status == .notRegistered || service.status == .notFound { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ControlError.helperUnavailable
    }
    static func validateCurrentInstallation() throws {
        let url = Bundle.main.bundleURL.resolvingSymlinksInPath()
        // Reject broken resource seals before touching either service registration.
        // Valid development builds retain their existing workflow.
        var code: SecStaticCode?, information: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess else { throw HelperInstallationError.invalidSignature }
        let info = information as? [String: Any]
        let certificates = info?[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let developerID = certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }?.hasPrefix("Developer ID Application:") == true
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        let helperURL = url.appendingPathComponent("Contents/Library/HelperTools/FandyFanHelper")
        var helperCode: SecStaticCode?, helperInformation: CFDictionary?
        let created = SecStaticCodeCreateWithPath(helperURL as CFURL, [], &helperCode)
        var helperStatus = created
        if let helperCode {
            helperStatus = SecStaticCodeCheckValidity(helperCode, flags, nil)
            _ = SecCodeCopySigningInformation(helperCode, SecCSFlags(rawValue: kSecCSSigningInformation), &helperInformation)
        }
        let helperInfo = helperInformation as? [String: Any]
        let team = info?[kSecCodeInfoTeamIdentifier as String] as? String
        let helperTeam = helperInfo?[kSecCodeInfoTeamIdentifier as String] as? String
        let match = team != nil && team == helperTeam && info?[kSecCodeInfoIdentifier as String] as? String == FandyIdentity.appIdentifier && helperInfo?[kSecCodeInfoIdentifier as String] as? String == FandyIdentity.helperIdentifier
        try HelperInstallationPolicy.validate(signatureStatus: SecStaticCodeCheckValidity(code, flags, nil),
                                             developerID: developerID, bundleURL: url, helperSignatureStatus: helperStatus, identitiesMatch: match)
    }
}


/// Resource-signature failures are installation problems, not missing background approval.
enum HelperInstallationError: Error, LocalizedError, Equatable {
    case invalidSignature, wrongLocation
    var errorDescription: String? {
        switch self {
        case .invalidSignature:
            "This copy of Fandy has an invalid app signature. Reinstall Fandy in Applications and open that copy."
        case .wrongLocation:
            "Move Fandy to Applications, then reopen it to enable fan control."
        }
    }
}
enum HelperInstallationPolicy {
    static func validate(signatureStatus: OSStatus, developerID: Bool, bundleURL: URL, helperSignatureStatus: OSStatus = errSecSuccess, identitiesMatch: Bool = true) throws {
        guard signatureStatus == errSecSuccess, helperSignatureStatus == errSecSuccess, identitiesMatch else { throw HelperInstallationError.invalidSignature }
        if developerID && bundleURL.resolvingSymlinksInPath().path != "/Applications/Fandy.app" {
            throw HelperInstallationError.wrongLocation
        }
    }
}
