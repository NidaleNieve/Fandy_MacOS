import Foundation
import Testing
@testable import FandyApp
import FandyCore

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
