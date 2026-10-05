import Foundation
import Testing
@testable import FandyCore

@Test func coolChassisDefaultMatchesLatestRequestedExport() throws {
    let profile = BuiltInProfiles.coolChassis
    #expect(profile.floor == 0 && !profile.automaticAtIdle && profile.defaultRevision == 3)
    #expect(profile.curves[2].points.prefix(2).map { [$0.temperature, $0.percent] } == [[25,0],[27.1,22]])
    #expect(profile.curves[3].points.prefix(2).map { [$0.temperature, $0.percent] } == [[32,0],[35.5,18]])
    try profile.validate()
}
@Test func oldFactoryComfortProfileLoadsWithZeroFloorButUserEditsArePreserved() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("profiles.json")
    var old = Profile(id: "cool-chassis", name: "Cool Chassis", bundled: true, curves: [BuiltInProfiles.chip, BuiltInProfiles.trackpad, BuiltInProfiles.actuator, BuiltInProfiles.airflow], floor: 20)
    try JSONEncoder().encode(ProfileArchive(profiles: [old])).write(to: file)
    var expected = BuiltInProfiles.coolChassis; expected.fanResponse = old.fanResponse
    #expect(ProfileStore(url: file).load().profiles.first { $0.id == old.id } == expected)
    old.curves[1].points[1].percent = 27
    try JSONEncoder().encode(ProfileArchive(profiles: [old])).write(to: file)
    #expect(ProfileStore(url: file).load().profiles.first { $0.id == old.id } == old)
}
@Test func profileExportNamesUseTheProfileNameWithoutDirectoryCharacters() {
    #expect(BuiltInProfiles.coolChassis.exportFilename == "Cool Chassis.json")
    var profile = BuiltInProfiles.school; profile.name = "Work/Study:Quiet"
    #expect(profile.exportFilename == "Work-Study-Quiet.json")
}
