import Foundation
import AppKit
import Testing
@testable import FandyCore
@testable import FandyApp

@MainActor private final class ApplicationGroupFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var catalog: [RunningProcess] = []
    let crossoverProcess = Process(), javaProcess = Process()
    let crossover: RunningProcess, java: RunningProcess
    init(executable: URL = URL(fileURLWithPath: "/bin/sleep")) throws {
        for process in [crossoverProcess, javaProcess] {
            process.executableURL = executable; process.arguments = ["60"]; try process.run()
        }
        let processes = ProcessCatalog.list(includeHelpers: true)
        let crossoverPID = crossoverProcess.processIdentifier, javaPID = javaProcess.processIdentifier
        let c = try #require(processes.first { $0.pid == crossoverPID })
        let j = try #require(processes.first { $0.pid == javaPID })
        crossover = RunningProcess(pid: c.pid, launched: c.launched, name: "CrossOver", bundleID: "example.crossover", icon: nil)
        java = RunningProcess(pid: j.pid, launched: j.launched, name: "java", bundleID: nil, icon: nil)
    }
    func model() -> AppModel {
        AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, applicationCatalog: { [unowned self] in self.catalog })
    }
    func rule() throws -> ProfileActivationDefault {
        try JSONDecoder().decode(ProfileActivationDefault.self, from: Data(#"{"kind":"application","launchWhenOpened":true,"applicationID":"example.crossover","applicationName":"CrossOver","applications":[{"id":"example.crossover","name":"CrossOver","kind":"bundle"},{"id":"java","name":"java","kind":"process"}]}"#.utf8))
    }
    func stopJava() { if javaProcess.isRunning { javaProcess.terminate() }; javaProcess.waitUntilExit() }
    func close() {
        for process in [crossoverProcess, javaProcess] { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor @Test func eitherApplicationCanLaunchProfileAndItEndsOnlyAfterBothClose() async throws {
    let f = try ApplicationGroupFixture(); defer { f.close() }
    let model = f.model(); model.setActivationDefault(try f.rule(), profileID: "gaming")
    f.catalog = [f.java]; model.refreshApplicationAvailability(force: true); model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "gaming")
    f.catalog = [f.crossover, f.java]; model.refreshApplicationAvailability(force: true); model.expireActivation()
    f.stopJava(); f.catalog = [f.crossover]; model.refreshApplicationAvailability(force: true); model.expireActivation()
    #expect(model.machine.selected.id == "gaming" && model.manualIntent != nil)
    f.crossoverProcess.terminate(); f.crossoverProcess.waitUntilExit(); f.catalog = []
    model.refreshApplicationAvailability(force: true); model.expireActivation()
    #expect(model.machine.selected.id == "system" && model.manualIntent == nil)
    await model.prepareForTermination()
}
@MainActor @Test func closingFirstApplicationKeepsProfileWhileSecondRemains() async throws {
    let f = try ApplicationGroupFixture(); defer { f.close() }
    let model = f.model(); model.setActivationDefault(try f.rule(), profileID: "gaming")
    f.catalog = [f.crossover]; model.refreshApplicationAvailability(force: true); model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "gaming")
    f.catalog = [f.crossover, f.java]; model.refreshApplicationAvailability(force: true); model.expireActivation()
    f.crossoverProcess.terminate(); f.crossoverProcess.waitUntilExit(); f.catalog = [f.java]
    model.refreshApplicationAvailability(force: true); model.expireActivation()
    #expect(model.machine.selected.id == "gaming" && model.manualIntent != nil)
    let overview = try #require(ProfileConditionOverviewRow.rows(profiles: model.profiles, automation: model.automation).first { $0.id == "gaming" })
    #expect(overview.trigger?.contains("java") == true && overview.limit.contains("all"))
    await model.prepareForTermination()
}
@MainActor @Test func manualApplicationGroupCanWaitForEitherAppAndMenuDurationOverridesIt() async throws {
    let f = try ApplicationGroupFixture(); defer { f.close() }
    let model = f.model(); model.setActivationDefault(try f.rule(), profileID: "gaming"); model.select("gaming")
    #expect(model.manualIntent != nil && model.machine.selected.id == "gaming")
    f.catalog = [f.java]; model.refreshApplicationAvailability(force: true); model.expireActivation()
    #expect(model.awaitingApplicationID == nil && model.machine.selected.id == "gaming")
    #expect(model.activationDescription.contains("java"))
    model.activateFor(seconds: 300); let deadline = model.activationDeadline
    f.stopJava(); f.catalog = []; model.refreshApplicationAvailability(force: true); model.expireActivation()
    #expect(model.machine.selected.id == "gaming" && model.activationDeadline == deadline && deadline != nil)
    await model.prepareForTermination()
}
@MainActor @Test func multipleRulesRemainProfileSpecificAndUndoableWithoutStartupTriggers() async throws {
    let f = try ApplicationGroupFixture(); defer { f.close() }
    f.catalog = [f.java]
    let model = f.model(); model.editorHistory.groupsByEvent = false
    model.editorHistory.beginUndoGrouping(); model.setActivationDefault(try f.rule(), profileID: "gaming"); model.editorHistory.endUndoGrouping()
    model.evaluateApplicationLaunches(); #expect(model.machine.selected.id == "system")
    model.editorHistory.undo(); #expect(model.automation.activationDefaults["gaming"] == nil)
    model.editorHistory.redo(); #expect(model.automation.activationDefaults["gaming"] == (try f.rule()))
    let duplicate = BuiltInProfiles.gaming.duplicated(); model.profiles.append(duplicate)
    model.editorHistory.beginUndoGrouping()
    model.setActivationDefault(try f.rule(), profileID: duplicate.id)
    model.editorHistory.endUndoGrouping()
    #expect(model.automation.activationDefaults["school"] == nil)
    let rule = try #require(model.automation.activationDefaults[duplicate.id])
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
    #expect((object["applications"] as? [[String: String]])?.count == 2)
    model.select("system"); for _ in 0..<4 { await model.tick() }
    f.catalog = []; model.refreshApplicationAvailability(force: true)
    f.catalog = [f.java]; model.refreshApplicationAvailability(force: true); model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "gaming")
    model.powerTransition(); model.refreshApplicationAvailability(force: true); model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "system")
    await model.prepareForTermination()
}

@MainActor @Test func addingExistingHelperProcessIsBaselineAndAllInstancesMustClose() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let name = "fandy-condition-" + UUID().uuidString
    let executable = directory.appendingPathComponent(name)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)
    let f = try ApplicationGroupFixture(executable: executable); defer { f.close() }
    let model = AppModel(storeURL: f.directory.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let data = try JSONSerialization.data(withJSONObject: ["kind": "application", "launchWhenOpened": true, "applications": [["id": name, "name": "Helper", "kind": "process"]]])
    let rule = try JSONDecoder().decode(ProfileActivationDefault.self, from: data)
    model.setActivationDefault(rule, profileID: "gaming"); model.evaluateApplicationLaunches()
    #expect(model.machine.selected.id == "system")
    model.select("gaming")
    f.stopJava(); model.refreshApplicationAvailability(force: true); model.expireActivation()
    #expect(model.machine.selected.id == "gaming" && model.manualIntent != nil)
    f.crossoverProcess.terminate(); f.crossoverProcess.waitUntilExit()
    model.refreshApplicationAvailability(force: true); model.expireActivation()
    #expect(model.machine.selected.id == "system" && model.manualIntent == nil)
    await model.prepareForTermination()
}
