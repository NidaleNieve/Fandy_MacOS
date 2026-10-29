import Foundation
import Testing
import FandyCore
@testable import FandyHelper

@Test func controllerStatusReusesOnlyAdvisoryResultsWhileAdmissionAlwaysChecksFresh() throws {
    var now = 10.0, scans = 0, conflict = false
    let probe = ControllerPresenceObservation(clock: { now }, inspect: { scans += 1; if conflict { throw ControlError.restorationUnverified } })
    try probe.requireExclusive()
    #expect(probe.statusBlocker() == nil && scans == 1)
    conflict = true
    #expect(throws: ControlError.restorationUnverified) { try probe.requireExclusive() }
    #expect(probe.statusBlocker() != nil && scans == 2)
    now += 0.6
    #expect(probe.statusBlocker() != nil && scans == 3)
    now = 1 // Backward clocks do not prolong a cached clean observation.
    _ = probe.statusBlocker(); #expect(scans == 4)
}
