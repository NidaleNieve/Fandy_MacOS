import Foundation
import Testing
@testable import FandyCore

@Test func processResourcesExposeOnlyCountersAndLegacyDiagnosticsRemainDecodable() throws {
    let sample = try ProcessResourceSample.capture()
    #expect(sample.footprintBytes > 0 && sample.residentBytes > 0)
    #expect(sample.userCPUSeconds >= 0 && sample.systemCPUSeconds >= 0)
    let old = try JSONDecoder().decode(HelperDiagnosticReport.self, from: Data(#"{"phase":"ready","progressAt":10,"fans":[]}"#.utf8))
    #expect(old.resources == nil)
    var report = old; report.resources = sample
    let data = try JSONEncoder().encode(report)
    #expect(try JSONDecoder().decode(HelperDiagnosticReport.self, from: data).resources == sample)
    let keys = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
    #expect(Set(keys.keys) == ["footprintBytes", "residentBytes", "userCPUSeconds", "systemCPUSeconds"])
}

@Test func workMetricsAccumulateFixedCounterPhasesEvenOnFailure() throws {
    final class Clock: @unchecked Sendable { var now: UInt64 = 100 }
    let clock = Clock(), work = BackgroundWorkMetrics(clock: { clock.now })
    work.measure(.sampling) { clock.now = 200 }
    enum Failure: Error, Equatable { case expected }
    #expect(throws: Failure.expected) {
        try work.measure(.sampling) { clock.now = 350; throw Failure.expected }
    }
    work.measure(.controllerScan) { clock.now = 450 }
    let samples = work.snapshot()
    #expect(samples.count == 2)
    #expect(samples.first { $0.phase == .sampling }?.calls == 2)
    #expect(samples.first { $0.phase == .sampling }?.cpuNanoseconds == 250)
    #expect(samples.first { $0.phase == .controllerScan }?.cpuNanoseconds == 100)
}

@Test func backgroundWireEncodingReleasesNativeTemporariesAndPreservesOwnedPayload() throws {
    final class Reference { weak var object: NSObject? }
    struct Payload: Encodable {
        let reference: Reference
        func encode(to encoder: any Encoder) throws {
            let object = NSObject(); reference.object = object
            _ = Unmanaged.passRetained(object).autorelease()
            var container = encoder.singleValueContainer(); try container.encode("owned payload")
        }
    }
    let reference = Reference()
    let data = try Wire.encode(Payload(reference: reference))
    #expect(reference.object == nil)
    #expect(try Wire.decode(String.self, from: data) == "owned payload")
}

@Test func activePublicationUsesCompletedObservationsWithoutCreatingExtraSamplingWork() {
    #expect(!HelperPollingPolicy.publishesStatus(elapsed: 0.6, activeLease: true, newObservation: false, recoveryActive: false, restorationPending: false))
    #expect(HelperPollingPolicy.publishesStatus(elapsed: 0.1, activeLease: true, newObservation: true, recoveryActive: false, restorationPending: false))
    #expect(HelperPollingPolicy.publishesStatus(elapsed: 1, activeLease: false, newObservation: false, recoveryActive: false, restorationPending: false))
    #expect(HelperPollingPolicy.publishesStatus(elapsed: 0.5, activeLease: false, newObservation: false, recoveryActive: true, restorationPending: false))
    #expect(HelperPollingPolicy.publishesStatus(elapsed: 0.5, activeLease: false, newObservation: false, recoveryActive: false, restorationPending: true))
}
