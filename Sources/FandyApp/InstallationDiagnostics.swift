import Foundation
import Security
import FandyCore

struct LaunchdObservation: Codable, Sendable, Equatable {
    var state: String
    var processID: Int?
    var lastExitCode: Int?
    var queryExitCode: Int32
}
struct InstallationObservation: Codable, Sendable {
    var location: String
    var appSignatureValid: Bool
    var helperSignatureValid: Bool
    var identitiesMatch: Bool
    var signingClassesMatch: Bool
    var launchd: LaunchdObservation
}
/// Fixed read-only service query and signature assessment, off the main actor.
/// Raw launchd output and signing identities are never retained in the report.
enum InstallationDiagnostics {
    static func parseLaunchd(_ text: String, exitCode: Int32) -> LaunchdObservation {
        var result = LaunchdObservation(state: exitCode == 113 ? "absent" : "unknown", queryExitCode: exitCode)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "state": if ["running", "waiting", "not running", "spawn scheduled", "exited"].contains(parts[1]) { result.state = parts[1] }
            case "pid": result.processID = Int(parts[1])
            case "last exit code": result.lastExitCode = Int(parts[1])
            default: break
            }
        }
        return result
    }
    static func collect(bundleURL: URL) -> InstallationObservation {
        let url = bundleURL.resolvingSymlinksInPath()
        let app = signature(url), helper = signature(url.appendingPathComponent("Contents/Library/HelperTools/FandyFanHelper"))
        let location = url.path == "/Applications/Fandy.app" ? "applications" : url.path.contains("/AppTranslocation/") ? "translocated" : "other"
        let matching = app.team != nil && app.team == helper.team && app.identifier == FandyIdentity.appIdentifier && helper.identifier == FandyIdentity.helperIdentifier
        return .init(location: location, appSignatureValid: app.valid, helperSignatureValid: helper.valid,
            identitiesMatch: matching, signingClassesMatch: app.developerID != nil && app.developerID == helper.developerID, launchd: queryLaunchd())
    }
    private static func signature(_ url: URL) -> (valid: Bool, team: String?, identifier: String?, developerID: Bool?) {
        var code: SecStaticCode?, information: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return (false, nil, nil, nil) }
        let valid = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil) == errSecSuccess
        _ = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        let info = information as? [String: Any]
        let certificates = info?[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let developerID = certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }.map { $0.hasPrefix("Developer ID Application:") }
        return (valid, info?[kSecCodeInfoTeamIdentifier as String] as? String, info?[kSecCodeInfoIdentifier as String] as? String, developerID)
    }
    private static func queryLaunchd() -> LaunchdObservation {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("fandy-query-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try Data().write(to: temporary, options: .atomic)
            let file = try FileHandle(forWritingTo: temporary); defer { try? file.close() }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["print", "system/" + FandyIdentity.launchDaemonPlist.replacingOccurrences(of: ".plist", with: "")]
            process.standardOutput = file; process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while process.isRunning && ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { process.terminate(); return .init(state: "query_timeout", queryExitCode: -1) }
            let input = try FileHandle(forReadingFrom: temporary); defer { try? input.close() }
            let bytes = try input.read(upToCount: 65_536) ?? Data()
            return parseLaunchd(String(decoding: bytes, as: UTF8.self), exitCode: process.terminationStatus)
        } catch { return .init(state: "query_unavailable", queryExitCode: -1) }
    }
}
