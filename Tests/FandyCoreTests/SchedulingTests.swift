import Foundation
import Testing
@testable import FandyCore

private func period(_ id: String = "school", _ day: Int = 1, _ start: Int = 510, _ end: Int = 990) -> WeeklyPeriod {
    WeeklyPeriod(profileID: id, weekday: day, startMinute: start, endMinute: end)
}
private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

@Test func weeklyRangesRejectZeroLengthBadDaysAndUnknownProfiles() throws {
    for p in [period("absent"), period("school", 0), period("school", 8), period("school", 1, -1), period("school", 1, 1440), period("school", 1, 500, 500), period("school", 1, 0, 1441)] {
        #expect(throws: ScheduleError.self) { try p.validate(profileIDs: ["school"]) }
    }
    try period("school", 1, 0, 1440).validate(profileIDs: ["school"])
}
@Test func overnightAndSundaySpillAreHalfOpen() {
    var config = AutomationConfiguration(); let p = period("school", 2, 1110, 145); config.periods = [p]
    #expect(ScheduleEngine.active(in: config, at: date("2026-10-06T18:29:00Z"), calendar: utc) == nil)
    #expect(ScheduleEngine.active(in: config, at: date("2026-10-06T18:30:00Z"), calendar: utc)?.id == p.id)
    #expect(ScheduleEngine.active(in: config, at: date("2026-10-07T02:24:59Z"), calendar: utc)?.id == p.id)
    #expect(ScheduleEngine.active(in: config, at: date("2026-10-07T02:25:00Z"), calendar: utc) == nil)
    config.periods = [period("school", 7, 1380, 90)]
    #expect(config.periods[0].segments == [WeekSegment(start: 10020, end: 10080), WeekSegment(start: 0, end: 90)])
    #expect(ScheduleEngine.active(in: config, at: date("2026-10-05T01:00:00Z"), calendar: utc) != nil)
}
@Test func overridePreservesBothSidesAndAllUnrelatedRanges() throws {
    let original = period(), unrelated = period("gaming", 4)
    let incoming = period("gaming", 1, 600, 700)
    let output = ScheduleEngine.overriding(incoming, in: [original, unrelated])
    #expect(output.contains(unrelated)); #expect(output.contains(incoming))
    #expect(output.filter { $0.profileID == "school" }.map { [$0.startMinute, $0.endMinute] } == [[510,600],[700,990]])
    var config = AutomationConfiguration(); config.periods = output
    try config.validate(profileIDs: ["school", "gaming"])
}
@Test func overnightConflictIsDetectedOnFollowingDayAndOverrideClipsIt() throws {
    let overnight = period("school", 2, 1110, 145), incoming = period("gaming", 3, 60, 120)
    #expect(ScheduleEngine.conflicts(incoming, in: [overnight]).count == 1)
    let output = ScheduleEngine.overriding(incoming, in: [overnight])
    #expect(output.filter { $0.profileID == "school" }.map { [$0.weekday,$0.startMinute,$0.endMinute] } == [[2,1110,1440],[3,0,60],[3,120,145]])
}
@Test func disabledAndAdjacentSchedulesDoNotConflict() {
    let left = period("school", 1, 0, 500), right = period("gaming", 1, 500, 600)
    #expect(ScheduleEngine.conflicts(right, in: [left]).isEmpty)
    var disabled = left; disabled.enabled = false
    #expect(ScheduleEngine.conflicts(period("gaming", 1, 1, 30), in: [disabled]).isEmpty)
}
@Test func pausesAreProfileScopedAndEndExclusive() {
    var config = AutomationConfiguration(); config.periods = [period()]
    config.pauses = [SchedulePause(profileID: "gaming", start: date("2026-10-05T00:00:00Z"), end: date("2026-10-06T00:00:00Z"))]
    #expect(ScheduleEngine.active(in: config, at: date("2026-10-05T10:00:00Z"), calendar: utc) != nil)
    config.pauses[0].profileID = nil; config.pauses[0].end = date("2026-10-05T10:00:00Z")
    #expect(ScheduleEngine.active(in: config, at: date("2026-10-05T09:59:00Z"), calendar: utc) == nil)
    #expect(ScheduleEngine.active(in: config, at: date("2026-10-05T10:00:00Z"), calendar: utc) != nil)
}
@Test func schedulesRespectTimeZonesAndDSTRepeatedHour() {
    var config = AutomationConfiguration(); config.periods = [period("school", 7, 60, 120)]
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
    #expect(ScheduleEngine.active(in: config, at: date("2026-11-01T05:30:00Z"), calendar: calendar) != nil)
    #expect(ScheduleEngine.active(in: config, at: date("2026-11-01T06:30:00Z"), calendar: calendar) != nil)
    #expect(ScheduleEngine.active(in: config, at: date("2026-11-01T07:00:00Z"), calendar: calendar) == nil)
}
@Test func activationExpiresOnTimeAndExactProcessInstanceExit() {
    let start = date("2026-10-03T10:00:00Z")
    #expect(!ActivationIntent(profileID: "max").expired(at: start.addingTimeInterval(999999), running: { _,_ in false }))
    let timed = ActivationIntent(profileID: "max", limit: .deadline(start.addingTimeInterval(300)))
    #expect(!timed.expired(at: start.addingTimeInterval(299), running: { _,_ in false }))
    #expect(timed.expired(at: start.addingTimeInterval(300), running: { _,_ in false }))
    let watched = ActivationIntent(profileID: "gaming", limit: .process(pid: 42, launched: start))
    #expect(!watched.expired(at: start, running: { $0 == 42 && $1 == start }))
    #expect(watched.expired(at: start, running: { $0 == 42 && $1 == start.addingTimeInterval(1) }))
}
@Test func textScheduleImportReportsFieldSpecificErrorsAndRejectsAuthority() throws {
    let text = #"{"version":1,"entries":[{"profile":"School","day":"Tuesday","start":"18:30","end":"02:25"}]}"#
    let result = try ScheduleTextImport.decode(text, profiles: BuiltInProfiles.all)
    #expect(result.periods[0].spansMidnight); #expect(result.periods[0].weekday == 2)
    for invalid in [text.replacingOccurrences(of: "18:30", with: "6:30"), text.replacingOccurrences(of: "School", with: "Other"), text.replacingOccurrences(of: "Tuesday", with: "Tues"), text.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"qualified\":true")] {
        #expect(throws: ScheduleError.self) { try ScheduleTextImport.decode(invalid, profiles: BuiltInProfiles.all) }
    }
    do { _ = try ScheduleTextImport.decode(text.replacingOccurrences(of: "18:30", with: "25:10"), profiles: BuiltInProfiles.all); Issue.record("Expected rejection") }
    catch { #expect(error.localizedDescription.contains("entries[0].start")) }
}
@Test func timeParserIsStrictAndPermitsMidnightOnlyForEnd() throws {
    #expect(try ScheduleEngine.parseTime("23:59") == 1439)
    #expect(try ScheduleEngine.parseTime("24:00", allowEndOfDay: true) == 1440)
    for value in ["24:00", "12:60", "-1:20", " 12:20", "1:20", "nan", "∞", "１２:１０"] { #expect(throws: ScheduleError.self) { try ScheduleEngine.parseTime(value) } }
}
@Test func fullConfigurationRoundTripExcludesRuntimeAuthorityAndProtectsBuiltins() throws {
    var automation = AutomationConfiguration(); automation.periods = [period()]; automation.preferences.menuSensors = ["role:cpuAverage"]; automation.preferences.showHelperProcesses = true
    let original = PortableConfiguration(profiles: BuiltInProfiles.all, automation: automation)
    let data = try ConfigurationInterchange.encode(original)
    #expect(try ConfigurationInterchange.decode(data) == original)
    let string = String(decoding: data, as: UTF8.self)
    for field in ["manualIntent", "signingTeam", "qualified", "lease", "pid", "helperIdentifier"] { #expect(!string.contains("\"" + field + "\"")) }
    var bad = original; bad.profiles[0].name = "Changed"
    #expect(throws: (any Error).self) { try ConfigurationInterchange.encode(bad) }
    #expect(throws: (any Error).self) { try ConfigurationInterchange.decode(Data(string.replacingOccurrences(of: "\"version\" : 2", with: "\"version\" : 2, \"manualIntent\":true").utf8)) }
}
@Test func profileExportRetainsScheduleWithFreshIdentifiers() throws {
    var config = AutomationConfiguration(); config.periods = [period()]; config.pauses = [SchedulePause(profileID: "school", start: Date(), end: Date().addingTimeInterval(100))]
    var custom = BuiltInProfiles.school.duplicated(); custom.name = "Shared"
    config.periods[0].profileID = custom.id; config.pauses[0].profileID = custom.id
    let data = try ScheduledProfileInterchange.encode(custom, automation: config)
    let one = try ScheduledProfileInterchange.decode(data, existingCount: 6)
    let two = try ScheduledProfileInterchange.decode(data, existingCount: 7)
    #expect(one.profiles[0].id != two.profiles[0].id)
    #expect(one.periods[0].profileID == one.profiles[0].id)
    #expect(one.pauses[0].profileID == one.profiles[0].id)
    #expect(!one.profiles[0].bundled); #expect(one.profiles[0].name == "Shared")
}
@Test func storedVersionOneMigratesWithoutActivatingAndVersionTwoPersistsSchedules() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("backup")) }
    let encoder = JSONEncoder()
    let data = try encoder.encode(ProfileArchive(profiles: BuiltInProfiles.all, previousSelection: "max"))
    var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]; root["version"] = 1; root.removeValue(forKey: "automation")
    try JSONSerialization.data(withJSONObject: root).write(to: url)
    let store = ProfileStore(url: url); #expect(store.load().automation.periods.isEmpty)
    #expect(store.load().automation.preferences.launchAtLogin)
    var config = AutomationConfiguration(); config.periods = [period()]
    try store.save(BuiltInProfiles.all, previousSelection: "max", automation: config)
    #expect(store.load().automation == config)
    #expect(store.load().issues.isEmpty)
}
@Test func corruptedAutomationIsDiscardedWithoutLosingValidProfiles() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    var config = PortableConfiguration(profiles: BuiltInProfiles.all, automation: .init()); config.automation.periods = [period("absent")]
    try JSONEncoder().encode(config).write(to: url)
    let result = ProfileStore(url: url).load()
    #expect(result.profiles.count == 6); #expect(result.automation.periods.isEmpty); #expect(!result.issues.isEmpty)
}
@Test func hostileImportsAreBoundedAndDuplicateEntriesRequireReview() throws {
    for data in [Data(repeating: 32, count: 1_048_577), Data((String(repeating: "[", count: 40) + String(repeating: "]", count: 40)).utf8)] {
        #expect(throws: (any Error).self) { try ConfigurationInterchange.decode(data) }
    }
    var config = AutomationConfiguration(); config.periods = [period(), period()]
    #expect(throws: ScheduleError.self) { try config.validate(profileIDs: ["school"]) }
    try config.validate(profileIDs: ["school"], allowConflicts: true)
}
@Test func protectedBuiltinInterchangePreservesFundamentalModeAndSchedule() throws {
    var config = AutomationConfiguration(); config.periods = [period("max")]
    let data = try ScheduledProfileInterchange.encode(BuiltInProfiles.maximum, automation: config)
    let decoded = try ScheduledProfileInterchange.decode(data, existingCount: 128)
    #expect(decoded.profiles.isEmpty); #expect(decoded.replacements == [BuiltInProfiles.maximum])
    #expect(decoded.periods[0].profileID == "max")
}
@Test func newPreferenceMetadataHasBackwardCompatibleDefaults() throws {
    let prefs = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
    #expect(prefs.launchAtLogin); #expect(prefs.use24HourTime); #expect(prefs.menuSensors.isEmpty)
    let config = try JSONDecoder().decode(AutomationConfiguration.self, from: Data(#"{"periods":[]}"#.utf8))
    #expect(config.pauses.isEmpty); #expect(config.preferences == prefs)
}

@Test func nestedAuthorityFieldsAndInvalidBooleanVersionsAreRejected() throws {
    let bytes = try ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: .init()))
    var object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    var automation = object["automation"] as! [String: Any]; automation["qualified"] = true; object["automation"] = automation
    #expect(throws: ScheduleError.self) { try ConfigurationInterchange.decode(JSONSerialization.data(withJSONObject: object)) }
    let text = #"{"version":true,"entries":[]}"#
    #expect(throws: ScheduleError.self) { try ScheduleTextImport.decode(text, profiles: BuiltInProfiles.all) }
}
