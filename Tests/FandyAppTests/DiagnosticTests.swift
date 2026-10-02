import Foundation
import Testing
import FandyCore
@testable import FandyApp

@Test func latencySummaryUsesNearestRankAndRejectsMalformedSamples() throws {
    let summary = try LatencySummary(seconds: [0.004, 0.001, 0.003, 0.002])
    #expect(summary.samples == 4); #expect(summary.medianMilliseconds == 2)
    #expect(summary.p95Milliseconds == 4); #expect(summary.maximumMilliseconds == 4)
    let invalid: [[Double]] = [[], [-1], [.nan], [.infinity]]
    for bad in invalid {
        #expect(throws: ControlError.invalidNumber) { try LatencySummary(seconds: bad) }
    }
}
@Test func productionNegativeProbeContainsNoAdmissibleLeaseOrTargets() throws {
    for probe in try ProductionSecurityProbe.cases() {
        switch probe.method {
        case .begin:
            if let decoded = try? Wire.decodeCommand(LeaseRequest.self, from: probe.data) {
                #expect(decoded.version != Wire.version)
            }
        case .targets:
            let decoded = try Wire.decodeCommand(TargetRequest.self, from: probe.data)
            #expect(decoded.targets.allSatisfy { $0.fanID == Int.max && $0.rpm > 30_000 })
        case .recovery:
            #expect(try RecoveryTrialRequest.decode(probe.data).action == .initial)
        }
    }
}
@Test func additionalDiagnosticsCannotAcceptCustomPayloadsOrDurations() throws {
    for action in [HelperDiagnosticAction.productionSecurity, .performance, .profilesSleep, .productionHeartbeat, .productionDisconnect, .productionQuit, .productionHold] {
        #expect(try HelperDiagnosticAction.parse(["Fandy", action.rawValue]) == action)
        #expect(throws: ControlError.malformedMessage) { try HelperDiagnosticAction.parse(["Fandy", action.rawValue, "--duration", "9999"]) }
    }
}
