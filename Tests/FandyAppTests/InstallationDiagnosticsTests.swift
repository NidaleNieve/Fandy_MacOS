import Foundation
import Testing
import FandyCore
@testable import FandyApp

@Test func launchdDiagnosticsRetainOnlyAllowlistedStateAndNumbers() throws {
    let text = """
    system/is.dsr.fandy.fan-service = {
      path = /ExampleAccount/private-person/Secret.app
      state = running
      pid = 1234
      last exit code = 78
      environment = { PRIVATE_TOKEN = secret }
    }
    """
    let report = InstallationDiagnostics.parseLaunchd(text, exitCode: 0)
    #expect(report.state == "running" && report.processID == 1234 && report.lastExitCode == 78)
    let data = try JSONEncoder().encode(report)
    #expect(!String(decoding: data, as: UTF8.self).contains("private-person"))
    #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
    #expect(InstallationDiagnostics.parseLaunchd("Could not find service", exitCode: 113).state == "absent")
    #expect(InstallationDiagnostics.parseLaunchd("state = unexpected private stuff", exitCode: 0).state == "unknown")
}

@MainActor @Test func diagnosticExportPreservesItsSchemaAndExcludesRuntimeReadings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
        simulation: true, capabilities: HardwareCapabilities(model: "Fixture"), clock: { 10 })
    func report() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: model.sanitizedDiagnostics()) as? [String: Any])
    }
    let empty = try report()
    #expect((empty["connectionFailure"] as? [String: Any])?.isEmpty == true)
    #expect(empty["installation"] == nil && empty["helperDiagnostic"] == nil)
    let keys = Set(empty.keys)
    model.hardwareError = "private exported message"
    model.snapshot = HardwareSnapshot(at: 10, sensors: [.init(.cpuPeak, 46.12345, at: 10)],
        fans: [.init(id: 0, min: 1000, max: 8000, actual: 7123.456)])
    model.helperFailure = .init(kind: .timeout, domain: "Fandy", code: 17, operation: "status")
    model.helperDiagnostic = .init(phase: "sensor_discovery", progressAt: 10)
    model.installationObservation = .init(location: "applications", appSignatureValid: true,
        helperSignatureValid: true, identitiesMatch: true, signingClassesMatch: true,
        launchd: .init(state: "running", processID: 1234, queryExitCode: 0))
    let populated = try report()
    #expect(Set(populated.keys) == keys.union(["installation", "helperDiagnostic"]))
    let failure = try #require(populated["connectionFailure"] as? [String: Any])
    #expect(Set(failure.keys) == ["kind", "domain", "code", "operation"])
    #expect(failure["code"] as? Int == 17 && failure["kind"] as? String == "timeout")
    #expect((populated["installation"] as? [String: Any])?["location"] as? String == "applications")
    #expect(populated["failureCodes"] as? [String] == ["monitoring_or_control_error"])
    let text = String(decoding: try model.sanitizedDiagnostics(), as: UTF8.self)
    #expect(!text.contains("private exported message") && !text.contains("46.12345") && !text.contains("7123.456"))
}
