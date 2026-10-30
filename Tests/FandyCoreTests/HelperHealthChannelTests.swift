import Foundation
import Testing
@testable import FandyCore

@Test func healthRepliesStayAvailableWhileHardwareQueueIsBlocked() throws {
    let cache = HelperStatusStore()
    cache.publish(HelperStatus(automaticVerified: false, bootstrap: .init()), at: 10)
    let blocked = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
    DispatchQueue(label: "fixture.blocked.hardware").async { entered.signal(); blocked.wait() }
    entered.wait(); defer { blocked.signal() }
    let started = Date()
    for _ in 0..<50 {
        let reply = try Wire.decode(HelperStatus.self, from: Wire.encode(cache.read(at: 11)))
        #expect(reply.bootstrap?.stage == .initializing && !reply.automaticVerified)
    }
    #expect(Date().timeIntervalSince(started) < 0.25)
    let owner = UUID(), gate = HelperRequestGate(); #expect(gate.connect(owner: owner))
    _ = try gate.admit(owner: owner, now: 10); _ = try gate.admit(owner: owner, now: 10)
    let health = try gate.admitStatus(owner: owner, now: 10)
    #expect(gate.isOpen(health)); gate.finish(health)
    #expect(gate.isOpen(try gate.admitRestoration(owner: owner)))
}
@Test func cachedHealthCannotConferFreshOwnershipAndLegacyResponsesDecode() throws {
    let cache = HelperStatusStore()
    var ready = HelperStatus(automaticVerified: true)
    ready.snapshot = HardwareSnapshot(at: 10, sensors: [], fans: [Fan(id: 0, min: 1000, max: 6000, actual: 1200)], pressure: .nominal)
    cache.publish(ready, at: 10)
    #expect(cache.read(at: 11).automaticVerified)
    #expect(!cache.read(at: 14).automaticVerified)
    let data = try Wire.encode(HelperStatus(automaticVerified: false))
    #expect(try Wire.decode(HelperStatus.self, from: data).diagnostic == nil)
    #expect(Wire.version == 2 && Wire.maxBytes == 16_384)
}
@Test func helperFailurePreservesCodesWithoutPersonalDescription() throws {
    let error = NSError(domain: NSCocoaErrorDomain, code: 4102, userInfo: [NSLocalizedDescriptionKey: "private installation path"])
    let failure = HelperFailure.connection(error, operation: "status")
    #expect(failure.kind == .authentication && failure.code == 4102 && failure.operation == "status")
    let data = try JSONEncoder().encode(failure)
    #expect(!String(decoding: data, as: UTF8.self).contains("private installation"))
    #expect(HelperFailure.connection(NSError(domain: NSCocoaErrorDomain, code: 4099), operation: "status").kind == .serviceUnavailable)
    #expect(HelperFailure.timeout(operation: "status").kind == .timeout)
}

@Test func maximumCatalogStatusAndOptionalDiagnosticsFitExistingWireLimit() throws {
    var value = HelperStatus(automaticVerified: false)
    let roles = SensorRole.allCases
    value.capabilities = HardwareCapabilities(model: "Mac17,9", sensors: roles.map {
        SensorEvidence(role: $0, keys: (0..<24).map { String(format: "T%03d", $0) }, state: .verified,
            source: String(repeating: "provenance", count: 200), limitation: "unresolved", displayName: $0.rawValue)
    })
    value.diagnostic = .init(phase: "sensor_discovery", progressAt: 10, fans: (0..<2).map { FanMetadataReport(id: $0) })
    value.diagnostic?.resources = try ProcessResourceSample.capture()
    value.diagnostic?.work = BackgroundWorkPhase.allCases.map {
        BackgroundWorkSample(phase: $0, calls: .max, cpuNanoseconds: .max)
    }
    let cache = HelperStatusStore(); cache.publish(value, at: 10)
    #expect(try Wire.encode(cache.read(at: 10)).count <= Wire.maxBytes)
}

@Test func independentHealthRateLimitLeavesRestorationAvailable() throws {
    let gate = HelperRequestGate(), owner = UUID(); #expect(gate.connect(owner: owner))
    for _ in 0..<30 { let ticket = try gate.admitStatus(owner: owner, now: 10); gate.finish(ticket) }
    #expect(throws: ControlError.excessiveMessages) { try gate.admitStatus(owner: owner, now: 10) }
    let release = try gate.admitRestoration(owner: owner); gate.finish(release)
    let later = try gate.admitStatus(owner: owner, now: 11.1); gate.finish(later)
}

@Test func stalledBootstrapRemainsResponsiveAndDoesNotBecomeDeadOrReady() {
    let cache = HelperStatusStore()
    var value = HelperStatus(automaticVerified: false, bootstrap: .init())
    value.diagnostic = .init(phase: "fan_discovery", progressAt: 10)
    cache.publish(value, at: 10)
    let delayed = cache.read(at: 14)
    #expect(delayed.diagnostic?.stalled == true)
    #expect(delayed.bootstrap?.stage == .initializing && !delayed.automaticVerified)
}
