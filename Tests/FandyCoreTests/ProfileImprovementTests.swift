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
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    #expect(files.count <= 4)
    for file in files {
        let data = try Data(contentsOf: file)
        for line in data.split(separator: 10) { _ = try JSONSerialization.jsonObject(with: Data(line)) }
    }
}
