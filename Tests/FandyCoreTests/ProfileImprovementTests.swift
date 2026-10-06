import Foundation
import Testing
@testable import FandyCore

@Test func interchangeCreatesFreshCustomIDsWithoutChangingDefinitions() throws {
    let original = BuiltInProfiles.coolChassis
    let bytes = try ProfileInterchange.encode([original])
    let imported = try ProfileInterchange.decode(bytes, existingCount: 6)
    #expect(imported.count == 1)
    #expect(imported[0].id != original.id && !imported[0].bundled)
    #expect(imported[0].name == original.name)
    #expect(imported[0].curves == original.curves)
    #expect(imported[0].floor == original.floor)
    #expect(imported[0].kind == .custom)
}
@Test func interchangeRejectsAuthorityProtectedIdentitiesAndWholeInvalidBatch() throws {
    let custom = BuiltInProfiles.school.duplicated()
    let encoded = try ProfileInterchange.encode([custom])
    var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    root["qualification"] = true
    #expect(throws: (any Error).self) { try ProfileInterchange.decode(JSONSerialization.data(withJSONObject: root), existingCount: 6) }
    root.removeValue(forKey: "qualification")
    var entries = try #require(root["profiles"] as? [[String: Any]])
    entries[0]["id"] = "system"; root["profiles"] = entries
    #expect(throws: (any Error).self) { try ProfileInterchange.decode(JSONSerialization.data(withJSONObject: root), existingCount: 6) }
    entries[0]["id"] = custom.id; entries[0]["floor"] = 101; root["profiles"] = entries
    #expect(throws: (any Error).self) { try ProfileInterchange.decode(JSONSerialization.data(withJSONObject: root), existingCount: 6) }
}
@Test func interchangeBoundsCountBytesDepthAndDuplicateIDs() throws {
    let valid = try ProfileInterchange.encode([BuiltInProfiles.school])
    #expect(throws: (any Error).self) { try ProfileInterchange.decode(valid, existingCount: 128) }
    #expect(throws: (any Error).self) { try ProfileInterchange.decode(Data(repeating: 32, count: 1_048_577), existingCount: 6) }
    let nested = Data((String(repeating: "[", count: 1000) + "0" + String(repeating: "]", count: 1000)).utf8)
    #expect(throws: (any Error).self) { try ProfileInterchange.decode(nested, existingCount: 6) }
    var root = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    let entries = try #require(root["profiles"] as? [[String: Any]])
    root["profiles"] = entries + entries
    #expect(throws: (any Error).self) { try ProfileInterchange.decode(JSONSerialization.data(withJSONObject: root), existingCount: 6) }
}
@Test func boundedReadRejectsOversizedFileAndPreservesBytes() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let bytes = Data(repeating: 32, count: 1_048_577)
    try bytes.write(to: url)
    #expect(throws: (any Error).self) { try ProfileStore.readBounded(url) }
    #expect(try Data(contentsOf: url) == bytes)
    try Data("small".utf8).write(to: url)
    #expect(try ProfileStore.readBounded(url) == Data("small".utf8))
}
@Test func persistenceActorRejectsOlderRevisionsIncludingAfterNewerFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProfileStore(url: directory.appendingPathComponent("profiles.json"))
    let persistence = ProfilePersistence(store: store)
    var newest = BuiltInProfiles.all; newest[2].floor = 23
    try await persistence.save(newest, selection: nil, revision: 3)
    try await persistence.save(BuiltInProfiles.all, selection: nil, revision: 2)
    #expect(store.load().profiles == newest)
    do { try await persistence.save([], selection: nil, revision: 5); Issue.record("Invalid collection saved") } catch {}
    try await persistence.save(BuiltInProfiles.all, selection: nil, revision: 4)
    #expect(store.load().profiles == newest)
}

@Test func recoveryReservesCapacityForProtectedBuiltins() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ProfileStore(url: directory.appendingPathComponent("profiles.json"))
    let customOnly = (0..<128).map { _ in BuiltInProfiles.school.duplicated() }
    let original = try JSONEncoder().encode(ProfileArchive(profiles: customOnly))
    try original.write(to: store.url)
    let loaded = store.load()
    #expect(loaded.profiles.count == 128 && !loaded.issues.isEmpty)
    #expect(Set(BuiltInProfiles.all.map(\.id)).isSubset(of: Set(loaded.profiles.map(\.id))))
    #expect(try Data(contentsOf: store.url) == original)
    try store.save(loaded.profiles, previousSelection: nil)
    #expect(store.load().issues.isEmpty)
}

@Test func concurrentDiagnosticRecordsRemainCompleteAndBounded() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = try RotatingDiagnostics(directory: directory, limit: 4096)
    let snapshot = fixture()
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<30 { group.addTask { try log.record(profile: "fixture", snapshot: snapshot) } }
        try await group.waitForAll()
    }
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
    #expect(files.count <= 4)
    for file in files {
        let data = try Data(contentsOf: file)
        for line in data.split(separator: 10) { _ = try JSONSerialization.jsonObject(with: Data(line)) }
    }
}

/// Filesystem and failure adapters expose writes through the same serial interface.
private final class PersistenceWrites: @unchecked Sendable {
    private let lock = NSLock()
    private var archives: [ProfileArchive] = []
    private var shouldFail = false
    var count: Int { lock.lock(); defer { lock.unlock() }; return archives.count }
    var latest: ProfileArchive? { lock.lock(); defer { lock.unlock() }; return archives.last }
    func failNext() { lock.lock(); defer { lock.unlock() }; shouldFail = true }
    func write(_ archive: ProfileArchive) throws {
        lock.lock(); defer { lock.unlock() }
        archives.append(archive)
        if shouldFail { shouldFail = false; throw ControlError.helperUnavailable }
    }
}

@Test func unchangedPersistenceAcknowledgesRevisionWithoutSelectionOnlyWrites() async throws {
    let writes = PersistenceWrites(), profiles = BuiltInProfiles.all
    let persistence = ProfilePersistence(write: { try writes.write($0) })
    try await persistence.save(profiles, selection: "system", revision: 1)
    try await persistence.save(profiles, selection: "max", revision: 3)
    #expect(writes.count == 1)
    var old = AutomationConfiguration(); old.preferences.defaultProfileID = "gaming"
    try await persistence.save(profiles, selection: "gaming", revision: 2, automation: old)
    #expect(writes.count == 1) // Even a skipped write advances the stale-revision fence.
    try await persistence.save(profiles, selection: "gaming", revision: 4, automation: old)
    #expect(writes.count == 2 && writes.latest?.automation == old)
    var edited = profiles; edited[2].floor = 12
    try await persistence.save(edited, selection: "system-plus", revision: 5, automation: old)
    #expect(writes.count == 3 && writes.latest?.profiles == edited)
}

@Test func failedPersistenceNeverAcknowledgesAndSameRevisionCanRetry() async throws {
    let writes = PersistenceWrites(), persistence = ProfilePersistence(write: { try writes.write($0) })
    try await persistence.save(BuiltInProfiles.all, selection: nil, revision: 1)
    var changed = AutomationConfiguration(); changed.preferences.defaultProfileID = "school"
    writes.failNext()
    await #expect(throws: ControlError.helperUnavailable) {
        try await persistence.save(BuiltInProfiles.all, selection: nil, revision: 3, automation: changed)
    }
    try await persistence.save(BuiltInProfiles.all, selection: nil, revision: 2)
    #expect(writes.count == 2)
    try await persistence.save(BuiltInProfiles.all, selection: nil, revision: 3, automation: changed)
    #expect(writes.count == 3 && writes.latest?.automation == changed)
    writes.failNext()
    await #expect(throws: ControlError.helperUnavailable) {
        try await persistence.save(BuiltInProfiles.all, selection: nil, revision: 4)
    }
    // A failed adapter may have written before throwing. Restore the previous successful
    // configuration through a real write, rather than trusting the old acknowledgement.
    try await persistence.save(BuiltInProfiles.all, selection: nil, revision: 5, automation: changed)
    #expect(writes.count == 5 && writes.latest?.automation == changed)
}

@Test(arguments: ["curve", "point", "target"])
func everyProfileImportRejectsUnknownNestedAuthorityFields(location: String) throws {
    var custom = BuiltInProfiles.school.duplicated(); custom.name = "Shared"
    let legacy = try ProfileInterchange.encode([custom])
    let current = try ScheduledProfileInterchange.encode(custom, automation: .init())
    let full = try ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all + [custom], automation: .init()))
    for (format, bytes) in [legacy, current, full].enumerated() {
        var root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var profiles = try #require(root["profiles"] as? [[String: Any]])
        let index = format == 2 ? profiles.count - 1 : 0
        if location == "target" {
            profiles[index]["targetTemperature"] = ["input": "chip", "celsius": 65, "qualified": true]
        } else {
            var curves = try #require(profiles[index]["curves"] as? [[String: Any]])
            if location == "curve" { curves[0]["qualified"] = true }
            else {
                var points = try #require(curves[0]["points"] as? [[String: Any]])
                points[0]["manualRPM"] = 8000; curves[0]["points"] = points
            }
            profiles[index]["curves"] = curves
        }
        root["profiles"] = profiles
        let hostile = try JSONSerialization.data(withJSONObject: root)
        if format == 0 {
            #expect(throws: ControlError.malformedMessage) { try ProfileInterchange.decode(hostile, existingCount: 6) }
        } else if format == 1 {
            #expect(throws: ScheduleError.self) { try ScheduledProfileInterchange.decode(hostile, existingCount: 6) }
        } else {
            #expect(throws: ScheduleError.self) { try ConfigurationInterchange.decode(hostile) }
        }
    }
}

@Test func sharedImportDepthScannerIgnoresEscapedBracesAndRejectsDeepUnknownFields() throws {
    var profile = BuiltInProfiles.school.duplicated(); profile.name = #"Braces [ { \"quoted\" } ]"#
    let bytes = try ProfileInterchange.encode([profile])
    #expect(try ProfileInterchange.decode(bytes, existingCount: 6).first?.name == profile.name)
    let nested = Data((#"{"version":1,"profiles":[],"extra":"# + String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33) + "}").utf8)
    #expect(throws: ControlError.malformedMessage) { try ProfileInterchange.decode(nested, existingCount: 6) }
    #expect(throws: ScheduleError.self) { try ConfigurationInterchange.decode(nested) }
}
