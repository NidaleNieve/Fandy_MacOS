import Foundation
import Testing
@testable import FandyCore

@Test func ingressBoundsConnectionsIncludingPendingDisconnects() {
    let gate = HelperRequestGate(), owners = (0..<8).map { _ in UUID() }
    for owner in owners { #expect(gate.connect(owner: owner)) }
    #expect(!gate.connect(owner: UUID())); #expect(!gate.connect(owner: owners[0]))
    #expect(gate.close(owner: owners[0])); #expect(!gate.close(owner: owners[0]))
    #expect(!gate.connect(owner: UUID()))
    gate.disconnected(owner: owners[0]); #expect(gate.connect(owner: UUID()))
}
@Test func ingressBoundsGlobalAndPerConnectionWorkBeforeQueueing() throws {
    let gate = HelperRequestGate(), a = UUID(), b = UUID(), c = UUID()
    for owner in [a,b,c] { #expect(gate.connect(owner: owner)) }
    let first = try gate.admit(owner: a, now: 10)
    _ = try gate.admit(owner: a, now: 10)
    #expect(throws: ControlError.excessiveMessages) { try gate.admit(owner: a, now: 10) }
    _ = try gate.admit(owner: b, now: 10); _ = try gate.admit(owner: b, now: 10)
    #expect(throws: ControlError.excessiveMessages) { try gate.admit(owner: c, now: 10) }
    gate.finish(first); gate.finish(first) // Completion races cannot free two slots.
    _ = try gate.admit(owner: c, now: 10)
    #expect(throws: ControlError.excessiveMessages) { try gate.admit(owner: c, now: 10) }
}
@Test func restorationHasReservedCapacityDespiteFloodAndRateLimit() throws {
    let gate = HelperRequestGate(), owner = UUID()
    #expect(gate.connect(owner: owner))
    for _ in 0..<10 { let t = try gate.admit(owner: owner, now: 10); gate.finish(t) }
    #expect(throws: ControlError.excessiveMessages) { try gate.admit(owner: owner, now: 10) }
    let release = try gate.admitRestoration(owner: owner)
    #expect(gate.isOpen(release))
    #expect(throws: ControlError.excessiveMessages) { try gate.admitRestoration(owner: owner) }
    gate.finish(release)
    #expect(gate.isOpen(try gate.admitRestoration(owner: owner)))
}
@Test func ingressRejectsMalformedSizesWithoutOccupyingHardwareCapacity() throws {
    let gate = HelperRequestGate(), owner = UUID()
    #expect(gate.connect(owner: owner))
    for bytes in [-1,0,Wire.maxBytes + 1,Int.max] {
        #expect(throws: ControlError.malformedMessage) { try gate.admit(owner: owner, bytes: bytes, now: 10) }
    }
    let ticket = try gate.admit(owner: owner, bytes: Wire.maxBytes, now: 10)
    #expect(gate.isOpen(ticket)); gate.finish(ticket)
    #expect(throws: ControlError.staleSession) { try gate.admit(owner: UUID(), now: 10) }
}
@Test func invalidatedConnectionMakesAllQueuedHardwareWorkInert() throws {
    let gate = HelperRequestGate(), owner = UUID()
    #expect(gate.connect(owner: owner))
    let work = try gate.admit(owner: owner, now: 10)
    let release = try gate.admitRestoration(owner: owner)
    #expect(gate.close(owner: owner))
    #expect(!gate.isOpen(work)); #expect(!gate.isOpen(release))
    #expect(gate.rejection(owner: owner) == nil)
    #expect(throws: ControlError.staleSession) { try gate.admitRestoration(owner: owner) }
    gate.disconnected(owner: owner)
    #expect(!gate.connect(owner: owner)) // No stale ticket can revive after UUID reuse.
    gate.finish(work); gate.finish(release)
    #expect(gate.connect(owner: owner)); #expect(!gate.isOpen(work))
}
@Test func rejectionNotificationsAreCoalescedAndIndependentOfOrdinaryTraffic() throws {
    let gate = HelperRequestGate(), owner = UUID()
    #expect(gate.connect(owner: owner))
    _ = try gate.admit(owner: owner, now: 10); _ = try gate.admit(owner: owner, now: 10)
    let notice = try #require(gate.rejection(owner: owner))
    for _ in 0..<20 { #expect(gate.rejection(owner: owner) == nil) }
    gate.finish(notice); #expect(gate.rejection(owner: owner) != nil)
    #expect(gate.isOpen(try gate.admitRestoration(owner: owner)))
}
@Test func disconnectedPeersCannotEvadeGlobalRestorationBound() throws {
    let gate = HelperRequestGate()
    var pending: [HelperRequestGate.Ticket] = []
    for _ in 0..<8 {
        let owner = UUID(); #expect(gate.connect(owner: owner))
        pending.append(try gate.admitRestoration(owner: owner))
        #expect(gate.close(owner: owner)); gate.disconnected(owner: owner)
    }
    let next = UUID(); #expect(gate.connect(owner: next))
    #expect(throws: ControlError.excessiveMessages) { try gate.admitRestoration(owner: next) }
    gate.finish(pending[0]); #expect(gate.isOpen(try gate.admitRestoration(owner: next)))
}
@Test func ingressInvalidClocksCannotAdmitOrdinaryWorkButPermitRelease() throws {
    let gate = HelperRequestGate(), owner = UUID()
    #expect(gate.connect(owner: owner))
    let initial = try gate.admit(owner: owner, now: 10); gate.finish(initial)
    for now in [Double.nan, .infinity, 9] {
        #expect(throws: ControlError.excessiveMessages) { try gate.admit(owner: owner, now: now) }
    }
    #expect(gate.isOpen(try gate.admitRestoration(owner: owner)))
}

@Test func concurrentAdmissionAndCompletionPreserveReservedReleaseCapacity() throws {
    let gate = HelperRequestGate(), owner = UUID()
    #expect(gate.connect(owner: owner))
    DispatchQueue.concurrentPerform(iterations: 64) { _ in
        if let ticket = try? gate.admit(owner: owner, now: 10) { gate.finish(ticket); gate.finish(ticket) }
        if let ticket = gate.rejection(owner: owner) { gate.finish(ticket) }
    }
    let release = try gate.admitRestoration(owner: owner)
    #expect(gate.isOpen(release)); gate.finish(release)
    #expect(gate.close(owner: owner)); gate.disconnected(owner: owner)
    #expect(gate.connect(owner: UUID()))
}
