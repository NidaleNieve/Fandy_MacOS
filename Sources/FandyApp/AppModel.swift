import SwiftUI
import AppKit
import FandyCore
import FandyHardware
import os
import ServiceManagement

@MainActor @Observable final class AppModel {
    var profiles: [Profile]
    var automation: AutomationConfiguration
    var manualIntent: ActivationIntent?
    var activationDeadline: Double?
    var watchedProcessName: String?
    var scheduledPeriodID: UUID?
    var blockedScheduleID: UUID?
    var scheduleReview: ScheduleReview?
    var sensorMenu = SensorMenuModel()
    var shortcutErrors: [String: String] = [:]
    let wallClock: @Sendable () -> Date
    private(set) var runningApplicationIDs: Set<String> = []
    private var applicationCatalogRefreshedAt = -Double.infinity
    let applicationCatalog: @MainActor () -> [RunningProcess]
    var isQuitting: Bool { quitting }
    func clockNow() -> Double { clock() }
    var editorSelection = "system-plus"
    var machine = ControlMachine()
    var snapshot: HardwareSnapshot?
    var issues: [String]
    var scenario: MockScenario = .comfortableSchool
    private(set) var simulation = false
    private var requestedSimulation: Bool
    private(set) var helperHealth: HelperHealth = .unavailable
    let capabilities: HardwareCapabilities
    var busy = false
    var renameRequest: ProfileRenameRequest?
    var draftError: String?
    var curveInput: CurveInput = .chip
    var hardwareError: String?
    var tickCount = 0
    private(set) var powerTransitionCount: UInt64 = 0
    private let mock = MockBackend()
    private let client: any PrivilegedFanClient
    private let helperAvailable: @MainActor () -> Bool
    private let clock: @Sendable () -> Double
    private var lifecycleToken = UUID()
    private var hardware: (any TemperatureSensorProvider)?
    private let injectedProvider: (any TemperatureSensorProvider)?
    private var loop: Task<Void, Never>?
    private var pendingSave: Task<Void, Never>?
    private let store: ProfileStore
    private let persistence: ProfilePersistence
    private var saveRevision: UInt64 = 0
    private var collectionTask: Task<Void, Never>?
    private(set) var savingCollection = false
    private(set) var unsavedChanges = false
    private(set) var saveError: String?
    let editorHistory = UndoManager()
    private var groupedOriginal: Profile?
    private var failedConfiguration: (profiles: [Profile], automation: AutomationConfiguration, selection: String, restore: Bool)?
    private var failedCollection: (profiles: [Profile], selection: String)?
    private var historyRevision: UInt64 = 0
    var canUndo: Bool { _ = historyRevision; return editorHistory.canUndo }
    var canRedo: Bool { _ = historyRevision; return editorHistory.canRedo }
    private let diagnostics: RotatingDiagnostics?
    private let logger = Logger(subsystem: FandyIdentity.logSubsystem, category: "controller")
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private let powerCenter: NotificationCenter
    private var freshness = SensorFreshnessMonitor()
    private var quitting = false
    private var terminationReady = false
    var canTerminate: Bool { terminationReady }
    func stop() {
        loop?.cancel(); loop = nil
        if let sleepObserver { powerCenter.removeObserver(sleepObserver) }
        if let wakeObserver { powerCenter.removeObserver(wakeObserver) }
        sleepObserver = nil; wakeObserver = nil
    }
    init(storeURL: URL? = nil, autoStart: Bool = true, simulation: Bool = false,
         provider: (any TemperatureSensorProvider)? = nil, client: (any PrivilegedFanClient)? = nil,
         capabilities: HardwareCapabilities? = nil, helperAvailable: (@MainActor () -> Bool)? = nil,
         powerCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         wallClock: @escaping @Sendable () -> Date = { Date() },
         applicationCatalog: @escaping @MainActor () -> [RunningProcess] = { ProcessCatalog.list(includeHelpers: false) },
         clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.simulation = simulation; self.requestedSimulation = simulation; self.injectedProvider = provider; self.hardware = provider
        self.client = client ?? FanXPCClient(); self.helperAvailable = helperAvailable ?? { HelperManager.installed }
        self.capabilities = capabilities ?? DeviceRegistry.current.capabilities
        self.machine = ControlMachine(chipPolicy: simulation ? .cpuGPU : self.capabilities.chipPolicy)
        self.clock = clock; self.wallClock = wallClock; self.applicationCatalog = applicationCatalog; self.powerCenter = powerCenter
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        store = ProfileStore(url: storeURL ?? root.appendingPathComponent("Fandy/profiles.json"))
        persistence = ProfilePersistence(store: store)
        diagnostics = try? RotatingDiagnostics(directory: (storeURL?.deletingLastPathComponent() ?? root.appendingPathComponent("Fandy")).appendingPathComponent("logs"))
        let loaded = store.load(); profiles = loaded.profiles; issues = loaded.issues; automation = loaded.automation
        // Lifecycle begins from System regardless of persisted selection.
        if autoStart { Task { [weak self] in self?.start() } }
    }
    var edited: Profile? { profiles.first { $0.id == editorSelection } }
    var helperRegistrationText: String {
        switch HelperManager.service.status {
        case .enabled: capabilities.canRestore ? "Helper active" : "Read-only helper active"
        case .requiresApproval: "Approval required in System Settings"
        case .notRegistered, .notFound: "Helper not installed"
        @unknown default: "Helper status unavailable"
        }
    }
    var ownership: FanOwnership { FanOwnership.observe(snapshot, now: clock()) }
    var preview: ProfilePreview? {
        guard let edited, let snapshot, edited.kind != .system else { return nil }
        return try? ShadowProfileEngine.evaluate(edited, snapshot: snapshot, now: simulation ? snapshot.sampledAt : clock(), chipPolicy: machine.chipPolicy)
    }
    func temperatureText(_ role: SensorRole) -> String {
        let estimate = !simulation && capabilities.chipPolicy == .conservativeEnvelope && [.cpuAverage, .gpuAverage].contains(role)
        return StatusPresentation.temperature(snapshot?.sensors.first { $0.role == role },
            now: simulation ? snapshot?.sampledAt ?? clock() : clock(), estimate: estimate)
    }
    func curveTemperature(_ curve: FanCurve) -> Double? {
        guard let snapshot else { return nil }
        return try? curve.temperature(in: snapshot, now: simulation ? snapshot.sampledAt : clock(), chipPolicy: machine.chipPolicy)
    }
    func sanitizedDiagnostics() throws -> Data {
        // Allowlist-only export: no arbitrary messages, names, paths or signing identity.
        let object: [String: Any] = [
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
            "model": HardwareSnapshotReader.machineModel(),
            "controllerState": machine.state.rawValue, "helperHealth": helperHealth.rawValue,
            "hardwareStage": capabilities.stage.rawValue, "ownership": ownership.rawValue,
            "compatibilityEvidence": capabilities.compatibilityEvidence.rawValue,
            "simulation": simulation, "unsavedChanges": unsavedChanges,
            "failureCodes": [hardwareError == nil ? nil : "monitoring_or_control_error", saveError == nil ? nil : "persistence_error"].compactMap { $0 }
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
    func canMove(_ direction: Int) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == editorSelection }), !profiles[index].bundled else { return false }
        let next = index + direction
        return profiles.indices.contains(next) && !profiles[next].bundled
    }
    func eligibility(_ profile: Profile) -> ProfileEligibility {
        ProfileEligibility.evaluate(profile, capabilities: capabilities, helper: helperHealth, snapshot: snapshot, now: clock())
    }
    func canActivate(_ profile: Profile) -> Bool {
        if simulation || profile.kind == .system { return true }
        if capabilities.permits(profile), !helperAvailable(), let snapshot,
           (try? snapshot.validate(now: clock(), required: profile.requiredSensors(chipPolicy: capabilities.chipPolicy))) != nil { return true }
        return eligibility(profile).allowed
    }
    var statusText: String {
        if !simulation {
            if let hardwareError { return hardwareError }
            if capabilities.canRestore && (machine.selected.kind != .system || machine.state != .system) { return controlStatus }
            switch ownership {
            case .appleObserved: return "Monitoring · Apple automatic observed"
            case .manualObserved: return "Monitoring · external manual control observed"
            case .unknown: return "Monitoring · fan ownership unavailable"
            }
        }
        if machine.automaticAtIdle { return "Simulation · Apple auto at idle" }
        return "Simulation · \(controlStatus)"
    }
    private var controlStatus: String {
        if machine.automaticAtIdle && machine.state == .customActive { return "\(machine.selected.name) · Apple auto at idle" }
        return switch machine.state {
        case .system: "System"
        case .initializingCustom: "Starting \(machine.selected.name)…"
        case .customActive: machine.selected.name
        case .restoringSystem: "Returning to System…"
        case .fault: "Fan state unverified"
        }
    }
    func isSelected(_ id: String) -> Bool {
        if !simulation {
            if id == "system" { return machine.selected.kind == .system && ownership == .appleObserved && (!capabilities.canRestore || machine.state == .system) }
            guard capabilities.canControl, helperHealth == .controlReady else { return false }
        }
        return (machine.state == .system || machine.state == .customActive) && machine.selected.id == id
    }
    func observePower() {
        guard !quitting else { return }
        if sleepObserver == nil {
            sleepObserver = powerCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.powerTransition() } }
        }
        if wakeObserver == nil {
            wakeObserver = powerCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.powerTransition() } }
        }
    }
    func start() {
        guard loop == nil, !quitting else { return }
        observePower(); configureLogin()
        loop = Task { [weak self] in
            // First-launch/reconnect handback is an actual verified transaction, not
            // an assumed state or a temperature-gated operation.
            if let self, !self.simulation, self.capabilities.canRestore, self.helperAvailable() {
                if let effect = try? self.machine.select(BuiltInProfiles.system) { await self.execute(effect) }
            }
            while !Task.isCancelled {
                guard self != nil else { break }; await self?.tick()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }
    func select(_ id: String, manual: Bool = true) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        if !canActivate(profile) { hardwareError = eligibility(profile).reason; return }
        if manual && profile == machine.selected && (machine.state == .customActive || machine.state == .initializingCustom) { applyActivationDefault(profile); return }
        if manual, !canUseActivationDefault(profile) { return }
        lifecycleToken = UUID(); requestedSimulation = simulation
        do {
            if !simulation && profile.kind != .system && !helperAvailable() {
                try HelperManager.install()
                guard HelperManager.installed else {
                    hardwareError = "Enable Fandy in Login Items & Extensions, then select the profile."
                    return
                }
            }
            let effect = try machine.select(profile)
            if manual {
                applyActivationDefault(profile)
            }
            logger.notice("Profile changed to \(profile.name, privacy: .public)")
            Task { await execute(effect) }
            save()
        } catch { draftError = error.localizedDescription }
    }
    func refreshApplicationAvailability(force: Bool = false) {
        guard force || (automation.activationDefaults.values.contains { $0.kind == .application } && clock() - applicationCatalogRefreshedAt >= 1) else { return }
        runningApplicationIDs = Set(applicationCatalog().filter { ProcessCatalog.isRunning(pid: $0.pid, launched: $0.launched) }.compactMap(\.bundleID))
        applicationCatalogRefreshedAt = clock()
    }
    func tick() async {
        guard !busy, !quitting else { return }
        refreshApplicationAvailability(); expireActivation(); expireScheduledOccurrence(); let token = lifecycleToken; busy = true; defer { busy = false }
        var restorationReport: RestorationReport?
        var monitoringReading: HardwareSnapshot?
        do {
            if simulation {
                await mock.setScenario(scenario)
                let reading = try await mock.snapshot()
                guard token == lifecycleToken, !quitting else { return }; expireActivation(); expireScheduledOccurrence()
                guard token == lifecycleToken else { return }; snapshot = reading
                if let snapshot {
                    if machine.selected.kind != .system { try freshness.check(snapshot, required: machine.selected.requiredSensors(chipPolicy: machine.chipPolicy), now: snapshot.sampledAt) }
                    await stepController(snapshot, now: snapshot.sampledAt)
                }
            } else {
                let reading: HardwareSnapshot
                var observedBlocker: String?
                if helperAvailable() {
                    let status = try await client.status()
                    guard token == lifecycleToken, !quitting else { return }
                    restorationReport = status.restoration
                    monitoringReading = status.snapshot
                    monitoringReading?.fans = []
                    // Automatic-looking telemetry cannot erase a failed release transaction.
                    // An idle external manual mode is a separate ownership conflict; it does
                    // not automatically request another release merely because status was read.
                    if capabilities.canRestore && status.restoration?.verified == false {
                        throw ControlError.restorationUnverified
                    }
                    guard let received = status.snapshot else { throw ControlError.helperUnavailable }
                    reading = received
                    observedBlocker = status.recoveryBlocker
                    helperHealth = status.manualQualified && !status.observationOnly && capabilities.canControl && status.fault == nil && observedBlocker == nil ? .controlReady : .monitoring
                } else {
                    if hardware == nil { hardware = try AppleSiliconSensorProvider() }
                    guard let provider = hardware else { throw ControlError.invalidSnapshot }
                    reading = try await provider.snapshot()
                    guard token == lifecycleToken, !quitting else { return }
                    helperHealth = .unavailable
                }
                expireActivation(); expireScheduledOccurrence()
                guard token == lifecycleToken else { return }
                if !reading.fans.isEmpty || machine.selected.kind != .system { try reading.validateFans(now: clock()) }
                snapshot = reading
                if capabilities.canRestore && !reading.fans.isEmpty {
                    if machine.selected.kind != .system {
                        guard capabilities.canControl, helperHealth == .controlReady else { throw ControlError.helperUnavailable }
                        try freshness.check(reading, required: machine.selected.requiredSensors(chipPolicy: machine.chipPolicy), now: clock())
                    }
                    await stepController(reading, now: clock())
                }
                hardwareError = observedBlocker ?? (reading.fans.isEmpty ? "Fan interface unavailable; temperature monitoring remains available." : nil)
            }
            tickCount += 1
            evaluateSchedule()
            sensorMenu.scheduleRefresh(selected: automation.preferences.menuSensors, simulation: simulation, snapshot: snapshot)
            if let snapshot, tickCount % 5 == 0 { diagnostics?.enqueue(profile:machine.selected.name,snapshot:snapshot) }
        } catch {
            guard token == lifecycleToken, !quitting else { return }
            automationFailed()
            sensorMenu.scheduleRefresh(selected: automation.preferences.menuSensors, simulation: simulation, snapshot: nil)
            if simulation { await execute(machine.fail(error)) }
            else {
                hardwareError = error.localizedDescription; snapshot = monitoringReading; helperHealth = .fault
                if capabilities.canRestore && helperAvailable() {
                    await execute(machine.observationFailed(error, restoration: restorationReport))
                }
            }
        }
    }
    private func stepController(_ reading: HardwareSnapshot, now: Double) async {
        let wasCustom = machine.selected.kind != .system
        let effect = machine.step(reading, now: now)
        if wasCustom && machine.selected.kind == .system && machine.fault != nil { automationFailed() }
        await execute(effect)
    }
    private func execute(_ effect: ControlEffect) async {
        if case .apply = effect { expireActivation(); expireScheduledOccurrence() }
        let token = lifecycleToken
        switch effect {
        case .restore(let generation), .apply(_, let generation, _, _): guard generation == machine.generation else { return }
        case .none: return
        }
        if !simulation {
            switch effect {
            case .restore(let generation):
                if helperAvailable() && capabilities.canRestore {
                    do { try await client.restoreAutomatic(); guard token == lifecycleToken else { return }; machine.restored(generation:generation,verified:true); hardwareError = nil }
                    catch { guard token == lifecycleToken else { return }; machine.restored(generation:generation,verified:false); hardwareError=error.localizedDescription }
                } else {
                    // An observation-only build never acquired a lease and cannot release an
                    // external controller. Only fresh independent evidence can show Apple ownership.
                    do {
                        if hardware == nil { hardware = try AppleSiliconSensorProvider() }
                        guard let reading = try await hardware?.snapshot() else { throw ControlError.invalidSnapshot }
                        guard token == lifecycleToken else { return }
                        try reading.validateFans(now: clock())
                        snapshot = reading
                        machine.restored(generation: generation, verified: reading.appleOwnershipObserved)
                        if machine.state == .system { hardwareError = nil }
                    } catch { guard token == lifecycleToken else { return }; machine.restored(generation: generation, verified: false); hardwareError = error.localizedDescription }
                }
            case .apply(let targets,let generation,_,let required):
                guard generation == machine.generation else { return }
                do { try await client.apply(targets,generation:generation,required:required); guard token == lifecycleToken else { return }; machine.applied(generation:generation) }
                catch { guard token == lifecycleToken else { return }; automationFailed(); await execute(machine.fail(error));hardwareError=error.localizedDescription }
            case .none: break
            }
            return
        }
        switch effect {
        case .none: return
        case .restore(let generation):
            do { try await mock.restoreAutomatic(); guard token == lifecycleToken else { return }; machine.restored(generation: generation, verified: true) }
            catch { guard token == lifecycleToken else { return }; machine.restored(generation: generation, verified: false); logger.error("Restoration unverified") }
        case .apply(let targets, let generation, _, _):
            guard generation == machine.generation else { return }
            do { try await mock.apply(targets, generation: generation); guard token == lifecycleToken else { return }; machine.applied(generation: generation) }
            catch { guard token == lifecycleToken else { return }; await execute(machine.fail(error)) }
        }
    }
    func registerConfigurationUndo(profiles previousProfiles: [Profile]? = nil, automation previousAutomation: AutomationConfiguration? = nil, selection previousSelection: String? = nil) {
        let previousProfiles = previousProfiles ?? profiles, previousAutomation = previousAutomation ?? automation, previousSelection = previousSelection ?? editorSelection
        editorHistory.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.restoreEditorConfiguration(previousProfiles, automation: previousAutomation, selection: previousSelection) }
        }
        editorHistory.setActionName("Edit Profiles"); historyRevision &+= 1
    }
    private func restoreEditorConfiguration(_ next: [Profile], automation config: AutomationConfiguration, selection: String) {
        guard !savingCollection, !quitting else { return }
        var config = config
        // Undo profile edits and automation rules; retain current global settings.
        config.preferences = automation.preferences
        config.preferences.shortcuts = config.preferences.shortcuts.filter { binding in binding.key == "menu" || next.contains { $0.id == binding.key } }
        do {
            try PortableConfiguration(profiles: next, automation: config).validate()
            registerConfigurationUndo()
            let activeID = machine.selected.id
            profiles = next; automation = config; editorSelection = selection; scheduleReview = nil
            if let replacement = next.first(where: { $0.id == activeID }) {
                if replacement != machine.selected {
                    lifecycleToken = UUID(); let effect = try machine.select(replacement); Task { await execute(effect) }
                }
            } else { clearActivation(); select("system") }
            draftError = nil; scheduleSave()
        } catch { draftError = error.localizedDescription }
    }
    func beginEditGroup() {
        guard groupedOriginal == nil, let edited, !edited.protected else { return }
        groupedOriginal = edited; editorHistory.beginUndoGrouping()
    }
    func endEditGroup() {
        guard let original = groupedOriginal else { return }
        if let current = profiles.first(where: { $0.id == original.id }), original != current { registerUndo(original) }
        groupedOriginal = nil; editorHistory.endUndoGrouping(); historyRevision &+= 1
    }
    func resetEditorHistory() {
        if groupedOriginal != nil { groupedOriginal = nil; editorHistory.endUndoGrouping() }
        editorHistory.removeAllActions(); historyRevision &+= 1
    }
    private func registerUndo(_ previous: Profile) {
        editorHistory.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.update(previous) }
        }
        editorHistory.setActionName("Edit Profile"); historyRevision &+= 1
    }
    func update(_ profile: Profile) {
        guard !savingCollection, !quitting else { return }
        do {
            try profile.validate()
            guard let index = profiles.firstIndex(where: { $0.id == profile.id }), !profiles[index].protected else { return }
            guard profiles[index] != profile else { return }
            failedCollection = nil; failedConfiguration = nil
            if groupedOriginal == nil { registerUndo(profiles[index]) }
            // The existing validated profile is retained if a draft is invalid.
            if machine.selected.id == profile.id {
                var renamed = machine.selected; renamed.name = profile.name
                if renamed == profile { try machine.updateSelectedName(from: profile) }
                else { lifecycleToken = UUID(); let effect = try machine.select(profile); Task { await execute(effect) } }
            }
            profiles[index] = profile; draftError = nil; scheduleSave()
        } catch { draftError = error.localizedDescription }
    }
    private func commitCollection(_ next: [Profile], selection: String) {
        guard !savingCollection, !quitting else { return }
        failedConfiguration = nil
        savingCollection = true; pendingSave?.cancel(); saveRevision &+= 1
        let revision = saveRevision, active = machine.selected.id
        collectionTask = Task {
            defer { savingCollection = false; collectionTask = nil }
            do {
                var nextAutomation = automation
                let ids = Set(next.map(\.id))
                nextAutomation.periods.removeAll { !ids.contains($0.profileID) }
                nextAutomation.pauses.removeAll { $0.profileID.map { !ids.contains($0) } ?? false }
                nextAutomation.activationDefaults = nextAutomation.activationDefaults.filter { ids.contains($0.key) }
                nextAutomation.preferences.shortcuts = nextAutomation.preferences.shortcuts.filter { $0.key == "menu" || ids.contains($0.key) }
                try await persistence.save(next, selection: active, revision: revision, automation: nextAutomation)
                registerConfigurationUndo(); automation = nextAutomation
                profiles = next; editorSelection = selection
                unsavedChanges = false; saveError = nil; failedCollection = nil
                if !next.contains(where: { $0.id == machine.selected.id }) && !quitting { select("system") }
            } catch { failedCollection = (next, selection); saveError = "Profile changes could not be saved." }
        }
    }
    func create() {
        var profile = BuiltInProfiles.systemPlus.duplicated(); profile.name = "Custom Profile"
        commitCollection(profiles + [profile], selection: profile.id)
    }
    func duplicate(_ id: String? = nil) {
        guard let profile = profiles.first(where: { $0.id == (id ?? editorSelection) }) else { return }; let copy = profile.duplicated()
        var config = automation; config.activationDefaults[copy.id] = config.activationDefaults[profile.id]
        commitConfiguration(profiles: profiles + [copy], automation: config, selection: copy.id)
    }
    func delete(_ id: String? = nil) {
        guard let profile = profiles.first(where: { $0.id == (id ?? editorSelection) }), !profile.bundled else { return }
        commitCollection(profiles.filter { $0.id != profile.id }, selection: editorSelection == profile.id ? "system-plus" : editorSelection)
    }
    func reset() {
        guard let original = BuiltInProfiles.all.first(where: { $0.id == editorSelection }), !original.protected else { return }; update(original)
    }
    func move(_ direction: Int) {
        guard canMove(direction), let index = profiles.firstIndex(where: { $0.id == editorSelection }) else { return }
        var next = profiles; next.swapAt(index, index + direction)
        commitCollection(next, selection: editorSelection)
    }
    func importProfiles(_ data: Data) {
        do {
            let imported = try ScheduledProfileInterchange.decode(data, existingCount: profiles.count)
            reviewPeriods(imported.periods, pauses: imported.pauses, profiles: imported.profiles, replacing: imported.replacements, defaults: imported.activationDefaults)
        } catch { draftError = "Import rejected: \(error.localizedDescription)" }
    }
    func commitConfiguration(profiles next: [Profile], automation nextAutomation: AutomationConfiguration, selection: String, restore: Bool = false) {
        guard !savingCollection, !quitting else { return }
        do { try PortableConfiguration(profiles: next, automation: nextAutomation).validate() }
        catch { draftError = error.localizedDescription; return }
        failedCollection = nil; failedConfiguration = nil
        savingCollection = true; pendingSave?.cancel(); saveRevision &+= 1
        let revision = saveRevision, admittedToken = lifecycleToken
        collectionTask = Task {
            defer { savingCollection = false; collectionTask = nil }
            do {
                try await persistence.save(next, selection: "system", revision: revision, automation: nextAutomation)
                if restore && lifecycleToken == admittedToken { clearActivation(); blockedScheduleID = nil; select("system", manual: false) }
                else if !next.contains(where: { $0.id == machine.selected.id }) {
                    clearActivation(); select("system")
                }
                else if let replacement = next.first(where: { $0.id == machine.selected.id }), replacement != machine.selected {
                    // Definition replacement follows the existing live-edit path. Scheduling
                    // must not cancel a manual duration/process watch for the same profile.
                    lifecycleToken = UUID()
                    do { let effect = try machine.select(replacement); Task { await execute(effect) } }
                    catch { automationFailed(); await execute(machine.fail(error)) }
                }
                registerConfigurationUndo(); profiles = next; automation = nextAutomation; editorSelection = selection
                unsavedChanges = false; saveError = nil; configureLogin()
            } catch {
                failedConfiguration = (next, nextAutomation, selection, restore)
                saveError = "Configuration was not changed: storage failed. Retry when storage is available."
            }
        }
    }
    func setSimulation(_ enabled: Bool) {
        guard enabled != requestedSimulation, !quitting else { return }
        clearActivation(); blockedScheduleID = nil
        requestedSimulation = enabled; lifecycleToken = UUID(); let token = lifecycleToken
        Task {
            guard token == lifecycleToken, enabled != simulation else { return }
            defer { if token == lifecycleToken { requestedSimulation = simulation } }
            if !simulation && capabilities.canRestore {
                await execute(machine.fail(ControlError.invalidProfile("Backend changed; System selected.")))
                guard token == lifecycleToken, machine.state == .system else { return }
            } else if simulation {
                await execute(machine.fail(ControlError.invalidProfile("Backend changed; System selected.")))
                guard token == lifecycleToken else { return }
            }
            machine = ControlMachine(chipPolicy: enabled ? .cpuGPU : capabilities.chipPolicy)
            simulation = enabled; snapshot = nil; hardware = injectedProvider
            freshness = SensorFreshnessMonitor(); hardwareError = nil; helperHealth = .unavailable
            await tick()
        }
    }
    func powerTransition() {
        clearActivation(); blockedScheduleID = nil
        powerTransitionCount &+= 1
        requestedSimulation = simulation
        lifecycleToken = UUID(); let token = lifecycleToken
        snapshot = nil; hardware = injectedProvider; freshness = SensorFreshnessMonitor(); helperHealth = .unavailable
        if simulation || capabilities.canRestore {
            let effect = machine.sleep()
            Task { guard token == lifecycleToken else { return }; await execute(effect) }
        } else { machine = ControlMachine(chipPolicy: simulation ? .cpuGPU : capabilities.chipPolicy); hardwareError = nil }
    }
    func simulateRestart() { Task { await mock.helperRestart(); await execute(machine.fail(ControlError.helperUnavailable)) } }
    func quit() {
        guard !quitting else { return }
        beginTermination()
        Task { await finishTermination(); NSApp.terminate(nil) }
    }
    func prepareForTermination() async {
        guard !quitting else { return }
        beginTermination(); await finishTermination()
    }
    private func beginTermination() {
        clearActivation(); lifecycleToken = UUID(); quitting = true; stop(); pendingSave?.cancel()
    }
    func waitForCollection() async { await collectionTask?.value }
    private func finishTermination() async {
        if simulation || capabilities.canRestore { await execute(machine.fail(ControlError.invalidProfile("App quit"))) }
        await waitForCollection()
        await saveLatest()
        // Observation never owned a lease; control failures still rely on the helper watchdog.
        terminationReady = true
    }
    func discardFailedConfiguration() { failedConfiguration = nil }
    private func scheduleSave() {
        unsavedChanges = true; pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await self?.saveLatest()
        }
    }
    func save() {
        if let failed = failedConfiguration { commitConfiguration(profiles: failed.profiles, automation: failed.automation, selection: failed.selection, restore: failed.restore) }
        else if let failed = failedCollection { commitCollection(failed.profiles, selection: failed.selection) }
        else { Task { await saveLatest() } }
    }
    private func saveLatest() async {
        guard !savingCollection else { return }
        saveRevision &+= 1
        let revision = saveRevision, current = profiles, selection = machine.selected.id, config = automation
        do {
            try await persistence.save(current, selection: selection, revision: revision, automation: config)
            guard revision == saveRevision, current == profiles, config == automation else { return }
            unsavedChanges = false; saveError = nil
        } catch {
            guard revision == saveRevision else { return }
            unsavedChanges = true; saveError = "Changes not saved. Retry when storage is available."
        }
    }
}
