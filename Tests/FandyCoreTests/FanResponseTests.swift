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

@Test func quietProfilesFollowCurvesAtHighTemperaturesWithoutHiddenEscalation() throws {
    var profile = Profile(name: "Capped", curves: [FanCurve(.chip, [(30,0),(70,50)])], fanResponse: 0)
    for pressure in [ThermalPressure.nominal, .fair] {
        var machine = ControlMachine(); _ = try machine.select(profile)
        for time in 0...45 {
            let temperature = time < 10 ? 75.0 : time < 20 ? 85 : 105
            let effect = machine.step(fixture(at: Double(time), cpu: temperature, pressure: pressure), now: Double(time))
            if case .apply(let targets, let generation, _, _) = effect {
                #expect(machine.percent <= 50)
                for target in targets { #expect(target.rpm <= (try fixture().fans.first { $0.id == target.fanID }!.rpm(percent: 50))) }
                machine.applied(generation: generation)
            }
        }
        #expect(machine.percent == 50)
    }
    profile.floor = 0
    for pressure in [ThermalPressure.serious, .critical, .unknown] {
        var machine = ControlMachine(); _ = try machine.select(profile)
        guard case .restore = machine.step(fixture(pressure: pressure), now: 10) else { Issue.record("Pressure must restore without maximum targets"); continue }
        #expect(machine.selected.kind == .system)
    }
}

@Test func freshStoppedEntryAndInheritedHighOutputRespectNewCeiling() throws {
    var machine = ControlMachine(); _ = try machine.select(BuiltInProfiles.maximum)
    let first = machine.step(fixture(at: 0), now: 0)
    if case .apply(_, let generation, _, _) = first { machine.applied(generation: generation) }
    #expect(machine.percent == 100)
    let low = Profile(name: "Quiet", curves: [], floor: 20, fanResponse: 0)
    _ = try machine.select(low)
    for time in 1...6 {
        var snapshot = fixture(at: Double(time)); for i in snapshot.fans.indices { snapshot.fans[i].actualRPM = 0; snapshot.fans[i].targetRPM = snapshot.fans[i].maximumRPM }
        if case .apply = machine.step(snapshot, now: Double(time)) { #expect(machine.percent <= 20) }
    }
    #expect(machine.percent <= 4.1)
    var lower = low; lower.floor = 1
    _ = try machine.select(lower)
    _ = machine.step(fixture(at: 7), now: 7)
    #expect(machine.percent <= 1)
}

@Test func quietSchoolDoesNotReacquireFansForOneSecondBurstAtIdle() throws {
    var machine = ControlMachine(); _ = try machine.select(BuiltInProfiles.school)
    for time in 0...4 {
        let effect = machine.step(fixture(at: Double(time), cpu: 40), now: Double(time))
        if case .restore(let generation) = effect { machine.restored(generation: generation, verified: true) }
    }
    #expect(machine.automaticAtIdle)
    for time in 5...12 {
        let effect = machine.step(fixture(at: Double(time), cpu: time == 5 ? 70 : 40), now: Double(time))
        if case .apply = effect { Issue.record("A brief burst acquired manual control") }
    }
    #expect(machine.automaticAtIdle)
    for time in 13...25 { _ = machine.step(fixture(at: Double(time), cpu: 85), now: Double(time)) }
    #expect(!machine.automaticAtIdle && machine.percent <= 52)
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

@Test func cpuGPUSelectionChangesDemandButRetainsFullSensorRequirements() throws {
    var profile = Profile(name: "Choice", curves: [FanCurve(.chip, [(30,0),(90,60)])])
    let snapshot = fixture(cpu: 40, gpu: 70)
    profile.chipSources = [.cpu]
    let cpu = try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10)
    #expect(cpu.byCurve[.chip] == 10 && cpu.safetyPercent == 0)
    profile.chipSources = [.gpu]
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10).byCurve[.chip] == 40)
    profile.chipSources = [.cpu, .gpu]
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10).byCurve[.chip] == 40)
    profile.chipSources = [.cpu]; profile.targetTemperature = .init(input: .chip, celsius: 60)
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10).targetPercent == 0)
    #expect(try ProfileEngine().evaluate(profile, snapshot: fixture(cpu: 40, gpu: 85), now: 10).percent == 10)
    profile.chipSources = []; profile.curves[0].enabled = false; profile.targetTemperature = nil
    #expect(try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 10).safetyPercent == 0)
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

@Test func helperWatchdogValidatesFullInputsWithoutIncreasingLowTargets() throws {
    let spy = FanSpy(); var pressure = ThermalPressure.nominal
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(), read: {
        var snapshot = spy.snapshot(); snapshot.thermalPressure = pressure; return snapshot
    }, clock: { spy.now })
    #expect(coordinator.startup()); for _ in 0..<5 { _ = coordinator.status() }
    let owner = UUID(), lease = try coordinator.begin(LeaseRequest(generation: 1, required: SensorRole.safety), owner: owner)
    let snapshot = try #require(coordinator.status().snapshot)
    try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
        targets: snapshot.fans.map { FanTarget($0.id, $0.minimumRPM) }), owner: owner)
    spy.hot = true; spy.now += 1; coordinator.watchdog()
    #expect(spy.fans.allSatisfy { $0.targetRPM == $0.minimumRPM && $0.mode == .manual })
    pressure = .serious; spy.now += 1; coordinator.watchdog()
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
    #expect(coordinator.lastRestoration?.verified == true)
}

@Test func controlSensorFailureAndPressureRestoreWithoutEscalation() throws {
    var machine = ControlMachine(); _ = try machine.select(BuiltInProfiles.school)
    var snapshot = fixture(at: 6, cpu: 60); snapshot.sensors.removeAll { $0.role == .gpuPeak }
    guard case .restore = machine.step(snapshot, now: 6) else { Issue.record("Missing input must restore"); return }
    #expect(machine.selected.kind == .system)
    machine.restored(generation: machine.generation, verified: true)
    _ = try machine.select(BuiltInProfiles.school)
    guard case .restore = machine.step(fixture(at: 7, pressure: .serious), now: 7) else { Issue.record("Thermal pressure must restore"); return }
}

@Test func bootstrapRetryScheduleIsFixedBoundedAndRejectsPermanentFailures() {
    var retry = HelperBootstrapRetry()
    let admitted = retry.beginAttempt(); #expect(admitted); #expect(retry.nextOffset(transient: true) == 1)
    #expect(retry.nextOffset(transient: false) == nil)
    let second = retry.beginAttempt(); #expect(second); #expect(retry.nextOffset(transient: true) == 3)
    let third = retry.beginAttempt(); #expect(third); #expect(retry.nextOffset(transient: true) == nil)
    let fourth = retry.beginAttempt(); #expect(!fourth)
    let status = HelperStatus(automaticVerified: false, observationOnly: true, fault: "Fan helper could not start")
    #expect(!status.manualQualified && !status.automaticVerified)
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

@Test func helperPreservesCappedTargetsAtHighValidTemperaturesAndRejectsSeverePressure() throws {
    for pressure in [ThermalPressure.nominal, .fair] {
        var safety = HelperSafety(); safety.restorationFinished(true)
        let owner = UUID(), initial = fixture(pressure: pressure)
        let lease = try safety.begin(owner: owner, generation: 1, required: SensorRole.safety, snapshot: initial, now: 10)
        for temperature in [75.0,85,105] {
            let snapshot = fixture(cpu: temperature, gpu: temperature, pressure: pressure)
            let requests = try snapshot.fans.map { FanTarget($0.id, try $0.rpm(percent: 50)) }
            let result = try safety.validateAndRenew(owner: owner, leaseID: lease.id, generation: 1,
                targets: requests, snapshot: snapshot, now: 10)
            #expect(result == requests)
        }
        for severe in [ThermalPressure.serious, .critical, .unknown] {
            let snapshot = fixture(pressure: severe)
            #expect(throws: ControlError.thermalPressure) {
                try safety.validateAndRenew(owner: owner, leaseID: lease.id, generation: 1,
                    targets: snapshot.fans.map { FanTarget($0.id,$0.minimumRPM) }, snapshot: snapshot, now: 10)
            }
        }
    }
}
