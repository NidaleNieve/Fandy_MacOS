import Foundation
import Testing
@testable import FandyApp
import FandyCore

@Test func leaseAdmissionRequiresFreshVerifiedAutomaticHardware() throws {
    let snapshot = HardwareSnapshot(at: 10, sensors: [], fans: [
        Fan(id: 0, min: 2300, max: 7800, actual: 2600),
        Fan(id: 1, min: 2350, max: 7900, actual: 2650)
    ])
    let status = HelperStatus(automaticVerified: true, manualQualified: true, snapshot: snapshot)
    #expect(LeaseAdmission.automaticAlreadyVerified(status, now: 11))
    #expect(!LeaseAdmission.automaticAlreadyVerified(status, now: 14))
    #expect(!LeaseAdmission.automaticAlreadyVerified(status, now: 9))
    var invalid = status
    invalid.snapshot?.fans[1].mode = .manual
    #expect(!LeaseAdmission.automaticAlreadyVerified(invalid, now: 11))
    invalid = status; invalid.fault = "write failure"
    #expect(!LeaseAdmission.automaticAlreadyVerified(invalid, now: 11))
    invalid = status; invalid.recoveryBlocker = "competing controller"
    #expect(!LeaseAdmission.automaticAlreadyVerified(invalid, now: 11))
    invalid = status; invalid.observationOnly = true
    #expect(!LeaseAdmission.automaticAlreadyVerified(invalid, now: 11))
    invalid = status; invalid.manualQualified = false
    #expect(!LeaseAdmission.automaticAlreadyVerified(invalid, now: 11))
    invalid = status; invalid.automaticVerified = false
    #expect(!LeaseAdmission.automaticAlreadyVerified(invalid, now: 11))
    invalid = status; invalid.version += 1
    #expect(!LeaseAdmission.automaticAlreadyVerified(invalid, now: 11))
    invalid = status; invalid.restoration = try Wire.decode(RestorationReport.self, from: Data("{\"fans\":[]}".utf8))
    #expect(!LeaseAdmission.automaticAlreadyVerified(invalid, now: 11))
    invalid = status; invalid.snapshot?.fans[1].minimumRPM = .nan
    #expect(!LeaseAdmission.automaticAlreadyVerified(invalid, now: 11))
}

@MainActor private final class ReleaseProbe {
    var calls = 0
    var waiting: CheckedContinuation<Void, any Error>?
    func release() async throws {
        calls += 1
        try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func complete(_ result: Result<Void, any Error> = .success(())) {
        let callback = waiting; waiting = nil; callback?.resume(with: result)
    }
}
@Test @MainActor func overlappingLifecycleReleasesShareOneRPCWithoutCachingSuccess() async throws {
    let flight = RestorationFlight(), probe = ReleaseProbe()
    let first = Task { try await flight.run { try await probe.release() } }
    for _ in 0..<20 { await Task.yield() }
    #expect(probe.calls == 1)
    let second = Task { try await flight.run { try await probe.release() } }
    for _ in 0..<20 { await Task.yield() }
    #expect(probe.calls == 1)
    probe.complete(); try await first.value; try await second.value
    let third = Task { try await flight.run { try await probe.release() } }
    for _ in 0..<20 { await Task.yield() }
    #expect(probe.calls == 2); probe.complete(); try await third.value
}
@Test @MainActor func failedReleaseReachesEveryWaiterAndNextRequestRetries() async throws {
    let flight = RestorationFlight(), probe = ReleaseProbe()
    let first = Task { try await flight.run { try await probe.release() } }
    for _ in 0..<20 { await Task.yield() }
    let second = Task { try await flight.run { try await probe.release() } }
    for _ in 0..<20 { await Task.yield() }
    probe.complete(.failure(ControlError.restorationUnverified))
    for task in [first,second] {
        do { try await task.value; Issue.record("Failed release was reported as success") }
        catch { #expect(error as? ControlError == .restorationUnverified) }
    }
    let retry = Task { try await flight.run { try await probe.release() } }
    for _ in 0..<20 { await Task.yield() }
    #expect(probe.calls == 2); probe.complete(); try await retry.value
}
@Test @MainActor func cancellingOneWaiterCannotCancelTheSharedSafetyRelease() async throws {
    let flight = RestorationFlight(), probe = ReleaseProbe()
    let first = Task { try await flight.run { try await probe.release() } }
    for _ in 0..<20 { await Task.yield() }
    first.cancel()
    let second = Task { try await flight.run { try await probe.release() } }
    for _ in 0..<20 { await Task.yield() }
    #expect(probe.calls == 1); probe.complete()
    try await first.value; try await second.value
}

@Test func cachedTargetObservationMustBeImmediatelyFreshCompleteAndHealthy() {
    let snapshot = HardwareSnapshot(at: 10, sensors: [SensorReading(.socPeak, 40, at: 10)], fans: [Fan(id: 0, min: 2300, max: 7800, actual: 2500, target: 2600, mode: .manual)])
    let status = HelperStatus(automaticVerified: false, manualQualified: true, snapshot: snapshot)
    #expect(TargetObservation.snapshot(status, now: 10.1, required: [.socPeak])?.id == snapshot.id)
    #expect(TargetObservation.snapshot(status, now: 10.3, required: [.socPeak]) == nil)
    #expect(TargetObservation.snapshot(status, now: 9, required: [.socPeak]) == nil)
    #expect(TargetObservation.snapshot(status, now: .nan, required: [.socPeak]) == nil)
    #expect(TargetObservation.snapshot(status, now: 10.1, required: [.airflowTop]) == nil)
    var invalid = status; invalid.snapshot?.sensors[0].health = .unverified
    #expect(TargetObservation.snapshot(invalid, now: 10.1, required: [.socPeak]) == nil)
    invalid = status; invalid.recoveryBlocker = "Conflict"
    #expect(TargetObservation.snapshot(invalid, now: 10.1, required: [.socPeak]) == nil)
    invalid = status; invalid.fault = "Failed release"
    #expect(TargetObservation.snapshot(invalid, now: 10.1, required: [.socPeak]) == nil)
}

@Test func leaseContinuationCannotExtendQualificationOrDropRequiredInputs() throws {
    let lease = try Wire.decode(ControlLease.self, from: Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"owner\":\"00000000-0000-0000-0000-000000000002\",\"generation\":1,\"renewedAt\":10,\"required\":[\"socPeak\"]}".utf8))
    let snapshot = HardwareSnapshot(at: 10, sensors: [SensorReading(.socPeak, 40, at: 10)], fans: [Fan(id: 0, min: 2300, max: 7800, actual: 2500, target: 2600, mode: .manual)])
    let status = HelperStatus(automaticVerified: false, manualQualified: true, snapshot: snapshot)
    #expect(LeaseContinuation.permits(lease, status: status, required: [.socPeak], now: 10.1))
    #expect(!LeaseContinuation.permits(lease, status: status, required: [], now: 10.1))
    #expect(!LeaseContinuation.permits(lease, status: status, required: [.socPeak,.trackpad], now: 10.1))
    #expect(!LeaseContinuation.permits(lease, status: status, required: [.socPeak], now: 10.5))
    var bounded = lease; bounded.expiresAt = 25
    #expect(!LeaseContinuation.permits(bounded, status: status, required: [.socPeak], now: 10.1))
    var released = status; released.automaticVerified = true; released.snapshot?.fans[0].mode = .automatic
    #expect(!LeaseContinuation.permits(lease, status: released, required: [.socPeak], now: 10.1))
}
