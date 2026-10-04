import Foundation
import Testing
@testable import FandyCore

func fixture(at now: Double = 10, cpu: Double = 48, gpu: Double = 44, trackpad: Double = 27, actuator: Double = 25, airflow: Double = 33, pressure: ThermalPressure = .nominal) -> HardwareSnapshot {
    let values: [(SensorRole,Double)] = [(.cpuAverage,cpu),(.gpuAverage,gpu),(.cpuPeak,cpu),(.gpuPeak,gpu),(.socPeak,cpu),(.trackpad,trackpad),(.actuator,actuator),(.airflowLeft,airflow),(.airflowTop,airflow),(.airflowRight,airflow),(.charger,33),(.powerSupply,33),(.wireless,32)]
    return HardwareSnapshot(at: now,sensors: values.map { SensorReading($0.0,$0.1,at:now,sequence:UInt64(now)) },fans:[Fan(id:0,min:2317,max:7826,actual:2400),Fan(id:1,min:2200,max:7400,actual:2300)],pressure:pressure)
}
@Test func interpolationAndEndpoints() throws {
    let curve=FanCurve(.chip,[(50,20),(60,40)])
    #expect(try curve.evaluate(55) == 30)
    #expect(try curve.evaluate(50) == 20)
    #expect(try curve.evaluate(60) == 40)
    #expect(try curve.evaluate(0) == 20)
    #expect(try curve.evaluate(120) == 40)
}
@Test func interpolationMonotonicProperty() throws {
    let curve=BuiltInProfiles.chip
    var previous=0.0
    for x in stride(from:0.0,through:125.0,by:0.125) { let value=try curve.evaluate(x); #expect(value >= previous && value <= 100); previous=value }
}
@Test func rejectsInvalidCurves() {
    for pairs: [(Double,Double)] in [[(50,20)],[(60,20),(50,40)],[(50,20),(50,40)],[(50,40),(60,20)],[(50,-1),(60,40)],[(50,20),(60,101)],[(.nan,20),(60,40)],[(50,.infinity),(60,40)],[(50,20),(.infinity,40)]] {
        #expect(throws: (any Error).self) { try FanCurve(.chip,pairs).validate() }
    }
    #expect(throws: (any Error).self) { try BuiltInProfiles.chip.evaluate(.nan) }
    #expect(throws: (any Error).self) { try BuiltInProfiles.chip.evaluate(.infinity) }
}
@Test func duplicateNodeIDsRejected() {
    var curve=BuiltInProfiles.chip;curve.points[1].id=curve.points[0].id
    #expect(throws: (any Error).self) { try curve.validate() }
}
@Test func allDefaultsValidateAndProtectedProfilesCannotChange() throws {
    for profile in BuiltInProfiles.all { try profile.validate() }
    var profile=BuiltInProfiles.system;profile.name="Other"
    #expect(throws:(any Error).self) { try profile.validate() }
    profile=BuiltInProfiles.maximum;profile.floor=50
    #expect(throws:(any Error).self) { try profile.validate() }
    try BuiltInProfiles.maximum.duplicated().validate()
}
@Test func twoIndependentFanRangesAndClamping() throws {
    let fans=fixture().fans
    #expect(try fans[0].rpm(percent:50) == 5071.5)
    #expect(try fans[1].rpm(percent:50) == 4800)
    #expect(try fans[0].rpm(percent:-50) == fans[0].minimumRPM)
    #expect(try fans[1].rpm(percent:150) == fans[1].maximumRPM)
    #expect(throws:(any Error).self) { try fans[0].rpm(percent:.nan) }
    #expect(throws:(any Error).self) { try Fan(id:0,min:4000,max:2000,actual:2000).validate() }
}
@Test func chipAggregationAndMaxOfIndependentCurves() throws {
    let summary=try ChipAggregation.summarize([45,50,55]);#expect(summary.average==50);#expect(summary.peak==55)
    #expect(throws:(any Error).self) { try ChipAggregation.summarize([]) }
    #expect(throws:(any Error).self) { try ChipAggregation.summarize([40,.nan]) }
    let snapshot=fixture(trackpad:31,actuator:29,airflow:44)
    let request=try ProfileEngine().evaluate(BuiltInProfiles.coolChassis,snapshot:snapshot,now:10)
    #expect(request.byCurve[.trackpad]==40);#expect(request.byCurve[.airflow]==55);#expect(request.percent==55)
}
@Test func airflowUsesHottestAndProximityCannotDriveComfort() throws {
    var snapshot=fixture();snapshot.sensors[snapshot.sensors.firstIndex{$0.role == .airflowRight}!].celsius=44
    snapshot.sensors[snapshot.sensors.firstIndex{$0.role == .charger}!].celsius=90
    #expect(try ProfileEngine().evaluate(BuiltInProfiles.coolChassis,snapshot:snapshot,now:10).percent==55)
    snapshot=fixture();snapshot.sensors[snapshot.sensors.firstIndex{$0.role == .charger}!].celsius=90
    #expect(try abs(ProfileEngine().evaluate(BuiltInProfiles.coolChassis,snapshot:snapshot,now:10).percent - 25.0 / 3.0) < 0.001)
}
@Test func disabledChipCurveCannotSuppressSafety() throws {
    var profile=BuiltInProfiles.coolChassis;profile.curves[0].enabled=false
    #expect(try ProfileEngine().evaluate(profile,snapshot:fixture(gpu:85),now:10).percent==100)
    #expect(throws:(any Error).self) { try ProfileEngine().evaluate(profile,snapshot:fixture(pressure:.serious),now:10) }
}
@Test func minimumFloorAndSchoolIdle() throws {
    var floored = BuiltInProfiles.coolChassis; floored.floor = 20
    #expect(try ProfileEngine().evaluate(floored,snapshot:fixture(),now:10).percent==20)
    #expect(try ProfileEngine().evaluate(BuiltInProfiles.school,snapshot:fixture(cpu:40,gpu:40),now:10).percent==0)
}
@Test func governorFastRiseSlowFallHysteresisAndSafety() throws {
    var governor=DemandGovernor()
    #expect(try governor.update(50,at:0)==10)
    #expect(try governor.update(50,at:1)==20)
    #expect(try governor.update(100,at:2,urgent:true)==100)
    #expect(try governor.update(99,at:3)==100)
    #expect(try governor.update(20,at:4)==100)
    #expect(try governor.update(20,at:8)==100)
    let lowered=try governor.update(20,at:9);#expect(lowered>=98 && lowered<100)
    #expect(throws:(any Error).self) { try governor.update(.nan,at:10) }
    #expect(throws:(any Error).self) { try governor.update(20,at:1) }
}
@Test func missingStaleCorruptAndUnverifiedSensorsFail() {
    for health in [ReadingHealth.missing,.stale,.corrupt,.unverified] {
        var snapshot=fixture();snapshot.sensors[0].health=health
        #expect(throws:(any Error).self) { try snapshot.value(.cpuAverage,now:10) }
    }
    var snapshot=fixture();snapshot.sensors.removeAll{$0.role == .gpuPeak}
    #expect(throws:(any Error).self) { try ProfileEngine().evaluate(BuiltInProfiles.gaming,snapshot:snapshot,now:10) }
    #expect(throws:(any Error).self) { try fixture().validate(now:14,required:SensorRole.safety) }
    for number in [Double.nan,.infinity,-100,0,200] { #expect(throws:(any Error).self) { try fixture(cpu:number).validate(now:10,required:SensorRole.safety) } }
}
@Test func stableValuesAreHealthyButStaleAcquisitionIsNot() throws {
    var monitor=SensorFreshnessMonitor()
    for t in 1...20 { try monitor.check(fixture(at:Double(t)),required:SensorRole.safety,now:Double(t)) }
    var stalled=fixture(at:21);for i in stalled.sensors.indices { stalled.sensors[i].sequence=20 }
    try monitor.check(stalled,required:SensorRole.safety,now:21)
    stalled.sampledAt=25;for i in stalled.sensors.indices { stalled.sensors[i].sampledAt=25 }
    #expect(throws:(any Error).self) { try monitor.check(stalled,required:SensorRole.safety,now:25) }
}
@Test func initializationAcknowledgementAndSensorRecovery() throws {
    var controller=ControlMachine();_ = try controller.select(BuiltInProfiles.gaming)
    for t in 1...4 { #expect(controller.step(fixture(at:Double(t)),now:Double(t)) == .none) }
    let effect=controller.step(fixture(at:5),now:5)
    guard case .apply(_,let generation,_,_) = effect else { Issue.record("Expected targets");return }
    #expect(controller.state == .initializingCustom);controller.applied(generation:generation);#expect(controller.state == .customActive)
    var bad=fixture(at:6);bad.sensors.removeAll{$0.role == .gpuPeak}
    guard case .restore(let reset)=controller.step(bad,now:6) else { Issue.record("Missing restore");return }
    controller.restored(generation:reset,verified:true);#expect(controller.state == .system);#expect(controller.selected.id == "system")
    #expect(controller.step(fixture(at:7),now:7) == .none)
    _ = try controller.select(BuiltInProfiles.gaming)
    for t in 8...11 { #expect(controller.step(fixture(at:Double(t)),now:Double(t)) == .none) }
}
@Test func invalidEditRetainsPreviousProfile() throws {
    var controller=ControlMachine();_ = try controller.select(BuiltInProfiles.gaming)
    let previous=controller.selected;var invalid=previous;invalid.curves[0].points[1].percent = -1
    #expect(throws:(any Error).self) { try controller.select(invalid) };#expect(controller.selected==previous)
}
@Test func rapidSwitchSystemRejectsLateAcknowledgements() throws {
    var controller=ControlMachine();_ = try controller.select(BuiltInProfiles.gaming);let old=controller.generation
    _ = try controller.select(BuiltInProfiles.school);_ = try controller.select(BuiltInProfiles.system)
    controller.applied(generation:old);#expect(controller.state == .restoringSystem)
    controller.restored(generation:old,verified:true);#expect(controller.state == .restoringSystem)
    controller.restored(generation:controller.generation,verified:true);#expect(controller.state == .system)
}
@Test func restorationFailureIsNeverReportedAsSystem() throws {
    var controller=ControlMachine();_ = try controller.select(BuiltInProfiles.system)
    controller.restored(generation:controller.generation,verified:false)
    #expect(controller.state == .fault);#expect(controller.fault != nil)
    #expect(controller.step(fixture(),now:10) == .restore(generation:controller.generation))
}
@Test func sleepWakeRequiresNewSelection() throws {
    var controller=ControlMachine();_ = try controller.select(BuiltInProfiles.gaming);_ = controller.sleep()
    controller.restored(generation:controller.generation,verified:true)
    #expect(controller.state == .system);#expect(controller.selected.id == "system")
}
@Test func idleAutomaticTransitionAndReacquisition() throws {
    var controller=ControlMachine();_ = try controller.select(BuiltInProfiles.systemPlus)
    for t in 1...20 {
        let effect=controller.step(fixture(at:Double(t),cpu:40,gpu:40),now:Double(t))
        if case .apply(_,let g,_,_) = effect { controller.applied(generation:g) }
        if case .restore(let g) = effect { controller.restored(generation:g,verified:true) }
    }
    #expect(controller.automaticAtIdle)
    #expect(controller.step(fixture(at:21,cpu:50,gpu:40),now:21) == .none)
    #expect(controller.step(fixture(at:22,cpu:50,gpu:40),now:22) == .none)
    if case .apply = controller.step(fixture(at:24,cpu:50,gpu:40),now:24) {} else { Issue.record("No reacquisition") }
}
@Test func helperLeaseValidationAndWatchdog() throws {
    let owner=UUID();var safety=HelperSafety();safety.restorationFinished(true)
    let lease=try safety.begin(owner:owner,generation:1,required:SensorRole.safety,snapshot:fixture(),now:10)
    #expect(!safety.expired(at:19.9));#expect(safety.expired(at:20))
    #expect(throws:(any Error).self) { try safety.validateAndRenew(owner:UUID(),leaseID:lease.id,generation:1,targets:[],snapshot:fixture(at:11),now:11) }
    let targets=fixture().fans.map{FanTarget($0.id,$0.minimumRPM)}
    let actual=try safety.validateAndRenew(owner:owner,leaseID:lease.id,generation:1,targets:targets,snapshot:fixture(at:11,gpu:85),now:11)
    #expect(actual.map(\.rpm)==fixture().fans.map(\.maximumRPM));#expect(safety.lease?.renewedAt==11)
    let disconnected = safety.disconnect(owner:owner); #expect(disconnected);#expect(safety.restoring);#expect(!safety.systemVerified)
    safety.restorationFinished(true);#expect(safety.systemVerified);#expect(safety.lease==nil)
}
@Test func helperRejectsInvalidFanRequestsAndDoesNotRenew() throws {
    let badTargets:[[FanTarget]] = [[FanTarget(0,2500)],[FanTarget(0,2500),FanTarget(0,2500)],[FanTarget(-1,2500),FanTarget(1,2500)],[FanTarget(Int.max,2500),FanTarget(1,2500)],[FanTarget(0,.nan),FanTarget(1,2500)],[FanTarget(0,.infinity),FanTarget(1,2500)],[FanTarget(0,0),FanTarget(1,2500)],[FanTarget(0,30_001),FanTarget(1,2500)]]
    for targets in badTargets {
        let owner=UUID();var safety=HelperSafety();safety.restorationFinished(true)
        let lease=try safety.begin(owner:owner,generation:1,required:SensorRole.safety,snapshot:fixture(),now:10)
        #expect(throws:(any Error).self) { try safety.validateAndRenew(owner:owner,leaseID:lease.id,generation:1,targets:targets,snapshot:fixture(at:11),now:11) }
        #expect(safety.lease?.renewedAt==10)
    }
}
@Test func helperStartupAndRestartRejectStaleState() throws {
    var safety=HelperSafety()
    #expect(throws:(any Error).self) { try safety.begin(owner:UUID(),generation:1,required:SensorRole.safety,snapshot:fixture(),now:10) }
    safety.restorationFinished(true);let owner=UUID();let lease=try safety.begin(owner:owner,generation:1,required:SensorRole.safety,snapshot:fixture(),now:10)
    safety=HelperSafety();safety.restorationFinished(true)
    #expect(throws:(any Error).self) { try safety.validateAndRenew(owner:owner,leaseID:lease.id,generation:1,targets:[],snapshot:fixture(),now:10) }
}
@Test func peerRequirementRejectsInjectionAndPinsExactApp() throws {
    let requirement=try PeerRequirement.make(team:"QMDP23SADL",identifier:FandyIdentity.appIdentifier)
    #expect(requirement.contains("anchor apple generic"));#expect(requirement.contains(FandyIdentity.appIdentifier))
    for value in ["bad\" or true", "", "local/fandy"] { #expect(throws:(any Error).self) { try PeerRequirement.make(team:"QMDP23SADL",identifier:value) } }
}
@Test func boundedWireRejectsMalformedAndExcessiveData() throws {
    let req=LeaseRequest(generation:1,required:SensorRole.safety)
    #expect(try Wire.decode(LeaseRequest.self,from:Wire.encode(req)).generation==1)
    for bytes in [Data(),Data("not json".utf8),Data(repeating:32,count:Wire.maxBytes+1),Data("{\"version\":1,\"generation\":-1,\"required\":[]}".utf8)] { #expect(throws:(any Error).self) { try Wire.decode(LeaseRequest.self,from:bytes) } }
}
@Test func messageFloodLimiterAndRecovery() {
    var limiter=MessageRateLimiter()
    for _ in 0..<10 { let allowed = limiter.allow(at:0); #expect(allowed) }; let flood = limiter.allow(at:0); #expect(!flood); let recovered = limiter.allow(at:1); #expect(recovered); let reversed = limiter.allow(at:-1); #expect(!reversed); let nonfinite = limiter.allow(at:.nan); #expect(!nonfinite)
}
@Test func profilePersistenceRoundTripAndBuiltinRecovery() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let store=ProfileStore(url:root.appendingPathComponent("profiles.json"));var profiles=BuiltInProfiles.all
    let copy=BuiltInProfiles.gaming.duplicated();profiles.append(copy);try store.save(profiles,previousSelection:copy.id)
    let loaded=store.load();#expect(loaded.issues.isEmpty);#expect(loaded.profiles==profiles)
    // Selection is metadata only; the machine never adopts it on startup.
    #expect(ControlMachine().selected.id=="system")
    let partial=try JSONEncoder().encode(ProfileArchive(profiles:[copy]));try partial.write(to:store.url)
    #expect(store.load().profiles.count==7)
}
@Test func corruptedProfilesArePreservedAndRecovered() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let store=ProfileStore(url:root.appendingPathComponent("profiles.json"));let corrupt=Data("broken".utf8);try corrupt.write(to:store.url)
    #expect(!store.load().issues.isEmpty);#expect(try Data(contentsOf:store.url)==corrupt)
    try store.save(BuiltInProfiles.all,previousSelection:nil)
    let backups=try FileManager.default.contentsOfDirectory(atPath:root.path).filter{$0.contains("corrupt")};#expect(backups.count==1)
}
@Test func independentlyDamagedProfileDoesNotHideBuiltins() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let store=ProfileStore(url:root.appendingPathComponent("profiles.json"))
    try Data("{\"version\":1,\"profiles\":[{\"id\":\"broken\"}]}".utf8).write(to:store.url)
    #expect(store.load().profiles==BuiltInProfiles.all);#expect(store.load().issues.count==1)
}
@Test func mockCrashWatchdogAndHelperRestart() async throws {
    let backend=MockBackend();let snapshot=try await backend.snapshot();let targets=try snapshot.fans.map{FanTarget($0.id,try $0.rpm(percent:30))}
    try await backend.apply(targets,generation:1);#expect(try await backend.snapshot().fans.allSatisfy{$0.mode == .manual})
    await backend.advanceWithoutHeartbeat(11);#expect(try await backend.snapshot().fans.allSatisfy{$0.mode == .automatic})
    try await backend.apply(targets,generation:2);await backend.helperRestart();#expect(try await backend.snapshot().fans.allSatisfy{$0.mode == .automatic})
    try await backend.apply(targets,generation:3);await backend.controllerDisconnected();#expect(try await backend.snapshot().fans.allSatisfy{$0.mode == .automatic})
}
