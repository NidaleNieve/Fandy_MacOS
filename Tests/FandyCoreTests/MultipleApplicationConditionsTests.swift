import Foundation
import Testing
@testable import FandyCore

private func multiApplicationRule(_ applications: [[String: String]]) throws -> ProfileActivationDefault {
    let object: [String: Any] = ["kind": "application", "launchWhenOpened": true,
        "applicationID": "example.crossover", "applicationName": "CrossOver", "applications": applications]
    return try JSONDecoder().decode(ProfileActivationDefault.self, from: JSONSerialization.data(withJSONObject: object))
}
private let appConditions = [["id": "example.crossover", "name": "CrossOver", "kind": "bundle"],
                             ["id": "java", "name": "java", "kind": "process"]]

@Test func multipleApplicationConditionsSurviveStorageAndPortableImports() throws {
    let rule = try multiApplicationRule(appConditions)
    var config = AutomationConfiguration(); config.activationDefaults["gaming"] = rule
    let data = try ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: config))
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let automation = try #require(root["automation"] as? [String: Any])
    let defaults = try #require(automation["activationDefaults"] as? [String: Any])
    let encoded = try #require(defaults["gaming"] as? [String: Any])
    #expect((encoded["applications"] as? [[String: String]])?.count == 2)
    #expect(try ConfigurationInterchange.decode(data).automation == config)
    let individual = try ScheduledProfileInterchange.decode(ScheduledProfileInterchange.encode(BuiltInProfiles.gaming, automation: config), existingCount: 6)
    #expect(individual.activationDefaults["gaming"] == rule)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProfileStore(url: directory.appendingPathComponent("profiles.json"))
    try store.save(BuiltInProfiles.all, previousSelection: nil, automation: config)
    #expect(store.load().automation.activationDefaults["gaming"] == rule)
}
@Test func legacyApplicationConditionMigratesToOnePortableEntry() throws {
    let rule = try JSONDecoder().decode(ProfileActivationDefault.self, from: Data(#"{"kind":"application","launchWhenOpened":true,"applicationID":"example.crossover","applicationName":"CrossOver"}"#.utf8))
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
    let apps = try #require(encoded["applications"] as? [[String: String]])
    #expect(apps.count == 1 && apps[0]["id"] == "example.crossover" && apps[0]["name"] == "CrossOver")
}
@Test func invalidMultipleApplicationConditionsCannotBeImported() throws {
    for entries in [appConditions + [appConditions[0]], [["id": "", "name": "Java", "kind": "process"]],
                    [["id": "java\n", "name": "Java", "kind": "process"]],
                    [["id": "/private/java", "name": "Java", "kind": "process"]],
                    Array(repeating: appConditions[0], count: 33)] {
        #expect(throws: (any Error).self) { try multiApplicationRule(entries).validate() }
    }
    var config = AutomationConfiguration(); config.activationDefaults["gaming"] = try multiApplicationRule(appConditions)
    let data = try ConfigurationInterchange.encode(.init(profiles: BuiltInProfiles.all, automation: config))
    var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var automation = try #require(root["automation"] as? [String: Any])
    var defaults = try #require(automation["activationDefaults"] as? [String: Any])
    defaults["gaming"] = ["kind": "application", "launchWhenOpened": true, "applications": [["id": "java", "name": "Java", "kind": "process", "shell": "ignored"]]]
    automation["activationDefaults"] = defaults; root["automation"] = automation
    #expect(throws: (any Error).self) { try ConfigurationInterchange.decode(JSONSerialization.data(withJSONObject: root)) }
}
