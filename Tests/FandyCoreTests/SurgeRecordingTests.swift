import Foundation
import Testing
@testable import FandyCore
private func surgeSample(_ time: Double, demand: Double = 20, actual: Double = 20) throws -> FanSurgeSample {
    var machine = ControlMachine(); _ = try machine.select(Profile(id: "test", name: "Test", curves: [], floor: demand))
    var snapshot = fixture(at: time)
    for i in snapshot.fans.indices { snapshot.fans[i].actualRPM = try snapshot.fans[i].rpm(percent: actual) }
    for _ in 0..<5 { snapshot.id = UUID(); _ = machine.step(snapshot, now: time) }
    return FanSurgeSample(timestamp: Date(timeIntervalSince1970: time), profileID: "test", snapshot: snapshot, control: ControlDiagnostic(machine: machine, snapshot: snapshot))
}
@Test func surgeCaptureIncludesPrehistoryAndFixedPostWindow() throws {
    var detector = SurgeDetector()
    var captured: FanSurgeEvent?
    for t in 0...100 {
        let sample = try surgeSample(Double(t), actual: t < 40 ? 20 : 50)
        if let event = detector.observe(sample) { captured = event }
    }
    let event = try #require(captured)
    #expect(event.triggeredAt == Date(timeIntervalSince1970: 40))
    #expect(event.samples.first?.timestamp == Date(timeIntervalSince1970: 10))
    #expect(event.samples.last?.timestamp == Date(timeIntervalSince1970: 100))
    #expect(event.samples.contains { $0.observedPercent >= 49.9 })
}
@Test func commandedSurgesCaptureButGradualOrDuplicateReadingsDoNot() throws {
    var detector = SurgeDetector(); var event: FanSurgeEvent?
    for t in 0...72 {
        let sample = try surgeSample(Double(t), demand: t < 10 ? 20 : 60)
        for _ in 0..<5 { if let e = detector.observe(sample) { event = e } }
    }
    #expect(event != nil)
    detector = SurgeDetector()
    for t in 0...120 { #expect(detector.observe(try surgeSample(Double(t), actual: 20 + Double(t)/2)) == nil) }
}
@Test func surgeFilesAreBoundedByCountBytesAgeAndPrivate() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let recorder = try SurgeRecorder(directory: dir, maxEvents: 2, maxBytes: 200_000, maxAge: 200)
    for t in 0...300 { try recorder.record(try surgeSample(Double(t), actual: t % 100 < 40 ? 20 : 50)) }
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
    #expect(files.count <= 2 && !files.isEmpty)
    #expect(try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) } <= 200_000)
    for file in files { #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600) }
    try recorder.prune(now: Date(timeIntervalSince1970: 1000))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
}
