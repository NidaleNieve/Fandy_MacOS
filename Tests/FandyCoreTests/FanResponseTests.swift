import Foundation
import Testing
@testable import FandyCore

@Test func elapsedTimeAverageSuppressesOneSecondBurstAndReachesSustainedDemand() throws {
    var filter = TimeWeightedDemand()
    #expect(try filter.update(0, at: 0, window: 3) == 0)
    #expect(try filter.update(30, at: 1, window: 3) == 0)
    #expect(try filter.update(0, at: 2, window: 3) == 10)
    #expect(try filter.update(0, at: 3, window: 3) == 10)
    #expect(try filter.update(0, at: 4, window: 3) == 10)
    #expect(try filter.update(0, at: 5, window: 3) == 0)
    filter.reset(); _ = try filter.update(0, at: 0, window: 3)
    _ = try filter.update(30, at: 1, window: 3)
    #expect(try filter.update(30, at: 2, window: 3) == 10)
    #expect(try filter.update(30, at: 3, window: 3) == 20)
    #expect(try filter.update(30, at: 4, window: 3) == 30)
}

@Test func averagingIsTimeWeightedDuplicateSafeAndConservativeWithoutHistory() throws {
    var filter = TimeWeightedDemand()
    #expect(try filter.update(40, at: 0, window: 3) == 40)
    filter.reset(); _ = try filter.update(0, at: 0, window: 3)
    _ = try filter.update(30, at: 0.5, window: 3)
    #expect(try filter.update(30, at: 1.5, window: 3) == 10)
    for _ in 0..<100 { #expect(try filter.update(30, at: 1.5, window: 3) == 10) }
    #expect(try filter.update(30, at: 3.5, window: 3) == 30)
    #expect(try filter.update(70, at: 7, window: 3) == 70)
    #expect(throws: ControlError.invalidNumber) { try filter.update(20, at: 6, window: 3) }
    #expect(try filter.update(20, at: 8, window: 3) == 20)
    #expect(try filter.update(90, at: 9, window: 0) == 90)
    for bad in [Double.nan, .infinity, -1, 101] {
        #expect(throws: ControlError.invalidNumber) { try filter.update(bad, at: 10, window: 3) }
    }
}

@Test func chipGuardSmoothsModerateBurstsButEscalatesImmediately() throws {
    var guardPolicy = SmoothedChipGuard()
    _ = try guardPolicy.update(snapshot: fixture(at: 0, cpu: 40), now: 0, policy: .cpuGPU)
    let burst = try guardPolicy.update(snapshot: fixture(at: 1, cpu: 70), now: 1, policy: .cpuGPU)
    #expect(burst.rawPercent == 27.5 && burst.enforcedPercent == 0 && !burst.immediate)
    let delayed = try guardPolicy.update(snapshot: fixture(at: 2, cpu: 40), now: 2, policy: .cpuGPU)
    #expect(abs(delayed.enforcedPercent - 27.5 / 3) < 0.0001)
    for (temperature, expected) in [(75.0, 40.0), (80, 70), (85, 100)] {
        let reading = try guardPolicy.update(snapshot: fixture(at: temperature, cpu: temperature), now: temperature, policy: .cpuGPU)
        #expect(reading.immediate && reading.enforcedPercent == expected)
    }
    let fair = try guardPolicy.update(snapshot: fixture(at: 86, cpu: 65, pressure: .fair), now: 86, policy: .cpuGPU)
    #expect(fair.immediate && fair.enforcedPercent == 15)
    for pressure in [ThermalPressure.serious, .critical, .unknown] {
        #expect(throws: ControlError.thermalPressure) { try guardPolicy.update(snapshot: fixture(at: 87, pressure: pressure), now: 87, policy: .cpuGPU) }
    }
    #expect(throws: (any Error).self) { try guardPolicy.update(snapshot: fixture(at: 87), now: 91, policy: .cpuGPU) }
}

@Test func risingGuardDoesNotMakeAnUnrelatedLargeProfileRequestImmediate() throws {
    var profile = Profile(name: "Large floor", curves: [], floor: 90)
    profile.fanResponse = 1
    var machine = ControlMachine(); _ = try machine.select(profile)
    for time in 0..<4 { _ = machine.step(fixture(at: Double(time), cpu: 40), now: Double(time)) }
    let effect = machine.step(fixture(at: 4, cpu: 56), now: 4)
    guard case .apply = effect else { Issue.record("Expected a target request"); return }
    #expect(machine.percent == 10) // A small guard rise must not jump to the 90% floor.
    _ = machine.step(fixture(at: 5, cpu: 85), now: 5)
    #expect(machine.percent == 100)
    _ = machine.step(fixture(at: 6, cpu: 40), now: 6)
    #expect(machine.percent == 100) // Preserve downward hold after escalation.
}

@Test func quietSchoolDoesNotReacquireFansForOneSecondModerateBurstAtIdle() throws {
    var machine = ControlMachine(); _ = try machine.select(BuiltInProfiles.school)
    for time in 0...4 {
        let effect = machine.step(fixture(at: Double(time), cpu: 40), now: Double(time))
        if case .restore(let generation) = effect { machine.restored(generation: generation, verified: true) }
    }
    #expect(machine.automaticAtIdle)
    for time in 5...12 {
        let effect = machine.step(fixture(at: Double(time), cpu: time == 5 ? 70 : 40), now: Double(time))
        if case .apply = effect { Issue.record("A brief moderate burst acquired manual control") }
    }
    #expect(machine.automaticAtIdle)
    #expect(machine.step(fixture(at: 13, cpu: 85), now: 13) != .none)
    #expect(machine.percent == 100 && !machine.automaticAtIdle)
}

@Test func responseDefaultsDecodeAndRoundTripWithoutChangingCurvesOrAutomation() throws {
    var school = BuiltInProfiles.school; school.fanResponse = 0.4; school.chipSources = [.gpu]
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(school)) as! [String: Any]
    object.removeValue(forKey: "fanResponse"); object.removeValue(forKey: "chipSources")
    let old = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.fanResponse == 0 && old.chipSources == [.cpu, .gpu] && old.curves == school.curves)
    object["id"] = "custom"
    let custom = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(custom.fanResponse == 1)
    let encoded = try ProfileInterchange.encode([school])
    let imported = try #require(ProfileInterchange.decode(encoded, existingCount: 0).first)
    #expect(imported.fanResponse == 0.4 && imported.chipSources == [.gpu] && imported.curves == school.curves)
    #expect(school.duplicated().fanResponse == 0.4 && school.duplicated().chipSources == [.gpu])
    for invalid in [Double.nan, .infinity, -0.1, 1.1] { var bad = school; bad.fanResponse = invalid; #expect(throws: (any Error).self) { try bad.validate() } }
    #expect(BuiltInProfiles.school.upwardRate == 2 && BuiltInProfiles.gaming.upwardRate == 10)
    var legacyTarget = Profile(name: "Target only", curves: [FanCurve(.chip, [(45,0),(85,100)], enabled: false)], targetTemperature: .init(input: .chip))
    object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyTarget)) as! [String: Any]
    object.removeValue(forKey: "chipSources"); object.removeValue(forKey: "fanResponse")
    legacyTarget = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: object))
    try legacyTarget.validate(); #expect(legacyTarget.chipSources == [.cpu, .gpu] && !legacyTarget.curves[0].enabled)
}

@Test func cpuGPUSelectionChangesCurveAndTargetButNeverRemovesFullGuard() throws {
    var profile = Profile(name: "Choice", curves: [FanCurve(.chip, [(30,0),(90,60)])])
    let snapshot = fixture(cpu: 40, gpu: 70)
    profile.chipSources = [.cpu]
    let cpu = try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10)
    #expect(cpu.byCurve[.chip] == 10 && cpu.safetyPercent == 27.5)
    profile.chipSources = [.gpu]
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10).byCurve[.chip] == 40)
    profile.chipSources = [.cpu, .gpu]
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10).byCurve[.chip] == 40)
    profile.chipSources = [.cpu]; profile.targetTemperature = .init(input: .chip, celsius: 60)
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10).targetPercent == 0)
    #expect(try ProfileEngine().evaluate(profile, snapshot: fixture(cpu: 40, gpu: 85), now: 10).percent == 100)
    profile.chipSources = []; profile.curves[0].enabled = false; profile.targetTemperature = nil
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10).safetyPercent == 27.5)
    profile.targetTemperature = .init(input: .chip)
    #expect(throws: (any Error).self) { try profile.validate() }
}

@Test func regionalSelectionRequiresCompleteFreshOperationalInputs() throws {
    var snapshot = fixture(cpu: 40, gpu: 70)
    snapshot.sensors.append(SensorReading(.cpuRegion, 45, at: 10))
    snapshot.sensors.append(SensorReading(.gpuRegion, 65, at: 10))
    snapshot.sensors[snapshot.sensors.firstIndex { $0.role == .socPeak }!].celsius = 65
    var profile = Profile(name: "Regions", curves: [FanCurve(.chip, [(30,0),(90,60)])], chipSources: [.cpu])
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10, chipPolicy: .conservativeEnvelope).byCurve[.chip] == 15)
    #expect(profile.requiredSensors(chipPolicy: .conservativeEnvelope) == [.socPeak, .cpuRegion])
    profile.chipSources = [.gpu]
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10, chipPolicy: .conservativeEnvelope).byCurve[.chip] == 35)
    snapshot.sensors.removeAll { $0.role == .gpuRegion }
    #expect(throws: (any Error).self) { try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10, chipPolicy: .conservativeEnvelope) }
}

@Test func helperEnforcesSmoothedFloorAndEscalatesWithoutGUI() throws {
    let spy = FanSpy(); var chip = 40.0
    let caps = HardwareCapabilities(model: "Test", stage: .qualifiedControl,
        sensors: SensorRole.allCases.map { SensorEvidence(role: $0, keys: ["Test"], state: .verified, source: "Fixture", limitation: "Synthetic") },
        topology: .verified, automaticRestoration: .verified, manualTransaction: .verified)
    let coordinator = HelperCoordinator(io: spy, capabilities: caps, read: {
        var snapshot = spy.snapshot()
        for index in snapshot.sensors.indices where SensorRole.safety.contains(snapshot.sensors[index].role) { snapshot.sensors[index].celsius = chip }
        return snapshot
    }, clock: { spy.now })
    #expect(coordinator.startup()); for _ in 0..<5 { _ = coordinator.status() }
    let owner = UUID(), lease = try coordinator.begin(LeaseRequest(generation: 1, required: SensorRole.safety), owner: owner)
    func command() throws {
        let snapshot = try #require(coordinator.status().snapshot)
        try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
                                           targets: snapshot.fans.map { FanTarget($0.id, $0.minimumRPM) }), owner: owner)
    }
    try command(); chip = 70; spy.now = 11; try command()
    #expect(coordinator.status().chipGuard?.enforcedPercent == 0)
    spy.now = 12; try command()
    #expect(coordinator.status().snapshot!.fans.allSatisfy { $0.targetRPM! > $0.minimumRPM })
    spy.now = 14; try command()
    #expect(coordinator.status().chipGuard?.enforcedPercent == 27.5)
    chip = 85; spy.now = 15; coordinator.watchdog()
    #expect(coordinator.status().snapshot!.fans.allSatisfy { $0.targetRPM == $0.maximumRPM })
    spy.now = 24; coordinator.watchdog()
    #expect(coordinator.lastRestoration?.verified == true)
}

@Test func adapterRechecksUseTheSameAuthoritativeElapsedTimeGuard() throws {
    let spy = FanSpy()
    let caps = HardwareCapabilities(model: "Test", stage: .qualifiedControl, sensors: [], topology: .verified,
                                    automaticRestoration: .verified, manualTransaction: .verified)
    let coordinator = HelperCoordinator(io: spy, capabilities: caps, read: { spy.snapshot() }, clock: { spy.now })
    #expect(coordinator.startup()); _ = coordinator.status()
    let evaluate = try #require(spy.guardEvaluator)
    #expect(try evaluate(fixture(at: 11, cpu: 70), 11) == 0)
    for _ in 0..<20 { #expect(try evaluate(fixture(at: 11, cpu: 70), 11) == 0) }
    #expect(abs(try evaluate(fixture(at: 12, cpu: 70), 12) - 27.5 / 3) < 0.0001)
    #expect(try evaluate(fixture(at: 14, cpu: 70), 14) == 27.5)
    #expect(try evaluate(fixture(at: 15, cpu: 85), 15) == 100)
    #expect(throws: (any Error).self) { try evaluate(fixture(at: 16), 20) }
    coordinator.powerTransition()
    #expect(coordinator.lastRestoration?.verified == true)
}

@Test func controlFailuresAndStaleGuardTelemetryStillRestoreImmediately() throws {
    var machine = ControlMachine(); _ = try machine.select(BuiltInProfiles.school)
    for time in 0...5 {
        let effect = machine.step(fixture(at: Double(time), cpu: 60), now: Double(time))
        if case .apply(_, let generation, _, _) = effect { machine.applied(generation: generation) }
    }
    let invalid = ChipGuardReading(rawPercent: 20, enforcedPercent: .nan, sampledAt: 6, immediate: false)
    guard case .restore = machine.step(fixture(at: 6, cpu: 60), now: 6, helperGuard: invalid) else { Issue.record("Invalid telemetry must restore"); return }
    #expect(machine.selected.kind == .system)
    machine.restored(generation: machine.generation, verified: true)
    #expect(machine.state == .system)
    _ = try machine.select(BuiltInProfiles.school)
    guard case .restore = machine.step(fixture(at: 7, pressure: .serious), now: 7) else { Issue.record("Thermal pressure must restore"); return }
}

@Test func quietAndFastGovernorsHaveExactDifferentUpwardRates() throws {
    for (response, expected) in [(0.0, 2.0), (0.5, 6.0), (1.0, 10.0)] {
        let profile = Profile(name: "Response", curves: [], floor: 50, fanResponse: response)
        var governor = DemandGovernor()
        #expect(try governor.update(50, at: 0, upwardRate: profile.upwardRate) == expected)
        #expect(try governor.update(50, at: 1, upwardRate: profile.upwardRate) == expected * 2)
    }
}

@Test func chipCheckboxesEnableOnlyTheChosenInputFromDisabledAndEmptyCurves() throws {
    for curves in [[], [FanCurve(.chip, [(45,0),(85,100)], enabled: false)]] {
        var profile = Profile(name: "Disabled", curves: curves)
        profile.setChipSource(.cpu, selected: true)
        #expect(profile.chipSources == [.cpu] && profile.curves[0].enabled)
        profile.setChipSource(.gpu, selected: true)
        #expect(profile.chipSources == [.cpu, .gpu])
        profile.setChipSource(.cpu, selected: false)
        #expect(profile.chipSources == [.gpu])
        profile.setChipSource(.gpu, selected: false)
        #expect(profile.chipSources.isEmpty && !profile.curves[0].enabled)
        try profile.validate()
        let roundTrip = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        #expect(roundTrip == profile)
    }
    var tampered = BuiltInProfiles.system; tampered.chipSources = [.cpu]
    let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(tampered))
    #expect(throws: (any Error).self) { try decoded.validate() }
}
