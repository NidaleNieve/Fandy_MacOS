import Foundation
import Testing
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
