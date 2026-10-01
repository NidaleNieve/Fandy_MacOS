import SwiftUI
import AppKit
import FandyCore
import FandyHardware
import os
import ServiceManagement

@MainActor @Observable final class AppModel {
    var profiles: [Profile]
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
    var draftError: String?
    var curveInput: CurveInput = .chip
    var hardwareError: String?
    var tickCount = 0
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
    private let diagnostics: RotatingDiagnostics?
    private let logger = Logger(subsystem: FandyIdentity.logSubsystem, category: "controller")
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var freshness = SensorFreshnessMonitor()
    private var quitting = false
    private var terminationReady = false
    var canTerminate: Bool { terminationReady }
    func stop() { loop?.cancel(); loop = nil }
    init(storeURL: URL? = nil, autoStart: Bool = true, simulation: Bool = false,
         provider: (any TemperatureSensorProvider)? = nil, client: (any PrivilegedFanClient)? = nil,
         capabilities: HardwareCapabilities? = nil, helperAvailable: (@MainActor () -> Bool)? = nil,
         clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.simulation = simulation; self.requestedSimulation = simulation; self.injectedProvider = provider; self.hardware = provider
        self.client = client ?? FanXPCClient(); self.helperAvailable = helperAvailable ?? { HelperManager.installed }
        self.capabilities = capabilities ?? SensorRegistry.capabilities.forMachine(HardwareSnapshotReader.machineModel())
        self.clock = clock
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        store = ProfileStore(url: storeURL ?? root.appendingPathComponent("Fandy/profiles.json"))
        diagnostics = try? RotatingDiagnostics(directory: (storeURL?.deletingLastPathComponent() ?? root.appendingPathComponent("Fandy")).appendingPathComponent("logs"))
        let loaded = store.load(); profiles = loaded.profiles; issues = loaded.issues
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
        return try? ShadowProfileEngine.evaluate(edited, snapshot: snapshot, now: simulation ? snapshot.sampledAt : clock())
    }
    func eligibility(_ profile: Profile) -> ProfileEligibility {
        ProfileEligibility.evaluate(profile, capabilities: capabilities, helper: helperHealth, snapshot: snapshot, now: clock())
    }
    func canActivate(_ profile: Profile) -> Bool { simulation || profile.kind == .system || eligibility(profile).allowed }
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
        switch machine.state {
        case .system: "System"
        case .initializingCustom: "Starting \(machine.selected.name)…"
        case .customActive: "\(machine.selected.name) · \(Int(machine.percent.rounded()))%"
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
    func start() {
        guard loop == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.powerTransition() } }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.powerTransition() } }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }
    func select(_ id: String) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        if !canActivate(profile) { hardwareError = eligibility(profile).reason; return }
        lifecycleToken = UUID(); requestedSimulation = simulation
        do {
            if !simulation && profile.kind != .system && !helperAvailable() { try HelperManager.install() }
            let effect = try machine.select(profile)
            logger.notice("Profile changed to \(profile.name, privacy: .public)")
            Task { await execute(effect) }
            save()
        } catch { draftError = error.localizedDescription }
    }
    func tick() async {
        guard !busy, !quitting else { return }; let token = lifecycleToken; busy = true; defer { busy = false }
        do {
            if simulation {
                await mock.setScenario(scenario)
                let reading = try await mock.snapshot()
                guard token == lifecycleToken, !quitting else { return }; snapshot = reading
                if let snapshot {
                    if machine.selected.kind != .system { try freshness.check(snapshot, required: machine.selected.requiredSensors, now: snapshot.sampledAt) }
                    await execute(machine.step(snapshot, now: snapshot.sampledAt))
                }
            } else {
                let reading: HardwareSnapshot
                if helperAvailable() {
                    let status = try await client.status()
                    guard token == lifecycleToken, !quitting else { return }
                    // Automatic-looking telemetry cannot erase a failed release transaction.
                    // An idle external manual mode is a separate ownership conflict; it does
                    // not automatically request another release merely because status was read.
                    if capabilities.canRestore && status.restoration?.verified == false {
                        throw ControlError.restorationUnverified
                    }
                    guard let received = status.snapshot else { throw ControlError.helperUnavailable }
                    reading = received
                    helperHealth = status.manualQualified && !status.observationOnly && capabilities.canControl ? .controlReady : .monitoring
                } else {
                    if hardware == nil { hardware = try AppleSiliconSensorProvider() }
                    guard let provider = hardware else { throw ControlError.invalidSnapshot }
                    reading = try await provider.snapshot()
                    guard token == lifecycleToken, !quitting else { return }
                    helperHealth = .unavailable
                }
                try reading.validateFans(now: clock())
                snapshot = reading
                if capabilities.canRestore {
                    if machine.selected.kind != .system {
                        guard capabilities.canControl, helperHealth == .controlReady else { throw ControlError.helperUnavailable }
                        try freshness.check(reading, required: machine.selected.requiredSensors, now: clock())
                    }
                    await execute(machine.step(reading, now: clock()))
                }
                hardwareError = nil
            }
            tickCount += 1
            if let snapshot, tickCount % 5 == 0 { try? diagnostics?.record(profile:machine.selected.name,snapshot:snapshot) }
        } catch {
            guard token == lifecycleToken, !quitting else { return }
            if simulation { await execute(machine.fail(error)) }
            else { hardwareError = error.localizedDescription; snapshot = nil; helperHealth = .fault; if capabilities.canRestore && helperAvailable() { await execute(machine.fail(error)) } }
        }
    }
    private func execute(_ effect: ControlEffect) async {
        let token = lifecycleToken
        switch effect {
        case .restore(let generation), .apply(_, let generation, _, _): guard generation == machine.generation else { return }
        case .none: return
        }
        if !simulation {
            switch effect {
            case .restore(let generation):
                if helperAvailable() && capabilities.canRestore {
                    do { try await client.restoreAutomatic(); guard token == lifecycleToken else { return }; machine.restored(generation:generation,verified:true) }
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
                        machine.restored(generation: generation, verified: reading.fans.allSatisfy { $0.mode == .automatic })
                    } catch { guard token == lifecycleToken else { return }; machine.restored(generation: generation, verified: false); hardwareError = error.localizedDescription }
                }
            case .apply(let targets,let generation,_,let required):
                guard generation == machine.generation else { return }
                do { try await client.apply(targets,generation:generation,required:required); guard token == lifecycleToken else { return }; machine.applied(generation:generation) }
                catch { guard token == lifecycleToken else { return }; await execute(machine.fail(error));hardwareError=error.localizedDescription }
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
    func update(_ profile: Profile) {
        do {
            try profile.validate()
            guard let index = profiles.firstIndex(where: { $0.id == profile.id }), !profiles[index].protected else { return }
            // The existing validated profile is retained if a draft is invalid.
            if machine.selected.id == profile.id { lifecycleToken = UUID(); let effect = try machine.select(profile); Task { await execute(effect) } }
            profiles[index] = profile; draftError = nil; scheduleSave()
        } catch { draftError = error.localizedDescription }
    }
    func create() {
        var profile = BuiltInProfiles.systemPlus.duplicated(); profile.name = "Custom Profile"
        profiles.append(profile); editorSelection = profile.id; save()
    }
    func duplicate() { guard let profile = edited else { return }; let copy = profile.duplicated(); profiles.append(copy); editorSelection = copy.id; save() }
    func delete() {
        guard let profile = edited, !profile.bundled else { return }
        if machine.selected.id == profile.id { select("system") }
        profiles.removeAll { $0.id == profile.id }; editorSelection = "system-plus"; save()
    }
    func reset() {
        guard let original = BuiltInProfiles.all.first(where: { $0.id == editorSelection }), !original.protected else { return }; update(original)
    }
    func move(_ direction: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == editorSelection }), !profiles[index].bundled else { return }
        let next = index + direction
        guard profiles.indices.contains(next), !profiles[next].bundled else { return }
        profiles.swapAt(index,next); save()
    }
    func setSimulation(_ enabled: Bool) {
        guard enabled != requestedSimulation, !quitting else { return }
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
            machine = ControlMachine()
            simulation = enabled; snapshot = nil; hardware = injectedProvider
            freshness = SensorFreshnessMonitor(); hardwareError = nil; helperHealth = .unavailable
            await tick()
        }
    }
    func powerTransition() {
        requestedSimulation = simulation
        lifecycleToken = UUID(); let token = lifecycleToken
        snapshot = nil; hardware = injectedProvider; freshness = SensorFreshnessMonitor(); helperHealth = .unavailable
        if simulation || capabilities.canRestore {
            let effect = machine.sleep()
            Task { guard token == lifecycleToken else { return }; await execute(effect) }
        } else { machine = ControlMachine(); hardwareError = nil }
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
        lifecycleToken = UUID(); quitting = true; loop?.cancel(); pendingSave?.cancel(); save()
    }
    private func finishTermination() async {
        if simulation || capabilities.canRestore { await execute(machine.fail(ControlError.invalidProfile("App quit"))) }
        // Observation never owned a lease; control failures still rely on the helper watchdog.
        terminationReady = true
    }
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.save()
        }
    }
    func save() { do { try store.save(profiles, previousSelection: machine.selected.id) } catch { issues = [error.localizedDescription] } }
}
