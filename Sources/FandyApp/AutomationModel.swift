import Foundation
import AppKit
import ServiceManagement
import FandyCore

struct ScheduleReview: Identifiable {
    let id = UUID()
    var remaining: [WeeklyPeriod]
    var accepted: [WeeklyPeriod]
    var addedProfiles: [Profile]
    var replacements: [Profile]
    var originals: [WeeklyPeriod]
    var currentBaseline: [WeeklyPeriod]? = nil
    var pauses: [SchedulePause]
    var activationDefaults: [String: ProfileActivationDefault] = [:]
    var conflict: [ScheduleConflict] { remaining.first.map { ScheduleEngine.conflicts($0, in: accepted) } ?? [] }
}

extension AppModel {

    var menuSelectionID: String? { machine.state == .fault ? nil : machine.selected.id }
    var canSetActivationLimit: Bool { machine.state != .fault && (machine.state != .restoringSystem || machine.selected.kind == .system) }
    func toggleProfile(_ id: String) { select(machine.selected.id == id && id != "system" && machine.state != .fault ? "system" : id) }
    func activationDefaultUnavailableReason(_ profile: Profile) -> String? {
        guard let rule = automation.activationDefaults[profile.id], rule.kind == .application else { return nil }
        return runningApplicationIDs.contains(rule.applicationID) ? nil : "\(rule.applicationName) is not running. Change this profile’s activation condition to use it now."
    }
    func canUseActivationDefault(_ profile: Profile) -> Bool {
        if automation.activationDefaults[profile.id]?.kind == .application { refreshApplicationAvailability(force: true) }
        if let reason = activationDefaultUnavailableReason(profile) { draftError = reason; return false }; return true
    }
    func rememberDefault(_ id: String) {
        if automation.preferences.defaultProfileID != id {
            previousDefaultProfileID = automation.preferences.defaultProfileID
            automation.preferences.defaultProfileID = id
        }
        defaultResumeBlocked = false
        saveDefaultPreference()
    }
    func applyActivationDefault(_ profile: Profile, remember: Bool = true) {
        clearActivation(); blockedScheduleID = nil
        let rule = automation.activationDefaults[profile.id] ?? .init()
        switch rule.kind {
        case .forever:
            if remember {
                // A deliberate selection supersedes the current occurrence, but
                // upcoming periods may still temporarily replace this default.
                blockedScheduleID = ScheduleEngine.active(in: automation, at: wallClock())?.id
                rememberDefault(profile.id)
            }
            else { manualIntent = ActivationIntent(profileID: profile.id) }
        case .duration:
            manualIntent = ActivationIntent(profileID: profile.id)
            activateFor(seconds: Double(rule.seconds))
        case .application:
            manualIntent = ActivationIntent(profileID: profile.id)
            if let process = applicationCatalog().first(where: { $0.bundleID == rule.applicationID }) { activateWhile(process) }
            else { clearActivation(); select("system", manual: false) }
        }
    }
    func setActivationDefault(_ rule: ProfileActivationDefault, profileID: String) {
        var next = automation; next.activationDefaults[profileID] = rule; setAutomation(next)
        if rule.kind == .application || rule.launchWhenOpened { refreshApplicationAvailability(force: true) }
    }
    var showsCancellation: Bool { manualIntent != nil || scheduledPeriodID != nil || blockedScheduleID != nil }
    var cancellationTitle: String {
        guard let intent = manualIntent else { return blockedScheduleID != nil ? "Resume Schedule" : "Cancel \(machine.selected.name)" }
        let end: Date
        if case .deadline(let deadline) = intent.limit { end = deadline } else { end = wallClock().addingTimeInterval(7 * 86400) }
        let resumes = ScheduleEngine.hasActivity(in: automation, after: wallClock(), before: end)
        return "Cancel \(machine.selected.name)" + (resumes ? " / Resume Schedule" : "")
    }

    var activationDescription: String {
        if let manualIntent {
            switch manualIntent.limit {
            case .forever: return "Manual · until changed"
            case .deadline(let date): return "Until \(formattedTime(date))"
            case .process: return "While \(watchedProcessName ?? "application") is running"
            }
        }
        if scheduledPeriodID != nil { return "Scheduled" }
        if blockedScheduleID != nil { return "Schedule paused for this occurrence · Resume Schedule to retry" }
        return "Default · " + (profiles.first { $0.id == automation.preferences.defaultProfileID }?.name ?? "System")
    }
    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = automation.preferences.use24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
    func activateForever() {
        if case .forever = manualIntent?.limit { clearActivation(); evaluateSchedule() }
        else if claimCurrentActivation(.forever) { rememberDefault(machine.selected.id) }
    }
    func activateFor(seconds: Double) {
        guard seconds.isFinite, seconds > 0, seconds <= 31 * 86400 else { draftError = "Duration must be positive and no longer than 31 days."; return }
        guard claimCurrentActivation(.deadline(wallClock().addingTimeInterval(seconds))) else { return }
        activationDeadline = clockNow() + seconds
    }
    func activateUntil(_ date: Date) { activateFor(seconds: date.timeIntervalSince(wallClock())) }
    func activateWhile(_ process: RunningProcess) {
        guard ProcessCatalog.isRunning(pid: process.pid, launched: process.launched) else { draftError = "The selected process has already exited."; return }
        guard claimCurrentActivation(.process(pid: process.pid, launched: process.launched)) else { return }
        watchedProcessName = process.name
    }
    @discardableResult private func claimCurrentActivation(_ limit: ActivationIntent.Limit) -> Bool {
        guard machine.state != .fault, (machine.state != .restoringSystem || machine.selected.kind == .system),
              let profile = profiles.first(where: { $0.id == machine.selected.id }), canActivate(profile) else {
            draftError = "Select an available profile before setting a duration."; return false
        }
        if limit != .forever, automation.preferences.defaultProfileID == profile.id {
            automation.preferences.defaultProfileID = profiles.contains { $0.id == previousDefaultProfileID } ? previousDefaultProfileID : "system"
            saveDefaultPreference()
        }
        manualIntent = ActivationIntent(profileID: profile.id, limit: limit)
        activationDeadline = nil; watchedProcessName = nil; scheduledPeriodID = nil; blockedScheduleID = nil
        return true
    }
    func cancelActivation() {
        if manualIntent == nil, blockedScheduleID != nil { resumeSchedule() }
        else if manualIntent == nil, let occurrence = scheduledPeriodID {
            clearActivation(); blockedScheduleID = occurrence; select("system", manual: false)
        } else if manualIntent == nil && machine.selected.kind != .system { select("system") }
        else { resumeSchedule() }
    }
    func resumeSchedule() {
        clearActivation(); blockedScheduleID = nil; defaultResumeBlocked = false
        select("system", manual: false)
    }
    func clearActivation() {
        manualIntent = nil; activationDeadline = nil; watchedProcessName = nil; scheduledPeriodID = nil
    }
    /// Called before sampling/commands. A delayed tick cannot renew an expired activation.
    func expireActivation() {
        guard let intent = manualIntent else { return }
        let expired = (activationDeadline.map { clockNow() >= $0 } ?? false) || intent.expired(at: wallClock(), running: ProcessCatalog.isRunning)
        if expired {
            if automation.preferences.defaultProfileID == intent.profileID {
                automation.preferences.defaultProfileID = profiles.contains { $0.id == previousDefaultProfileID } ? previousDefaultProfileID : "system"
                saveDefaultPreference()
            }
            clearActivation(); select("system", manual: false)
        }
    }
    func expireScheduledOccurrence() {
        guard manualIntent == nil, let scheduledPeriodID,
              ScheduleEngine.active(in: automation, at: wallClock())?.id != scheduledPeriodID else { return }
        self.scheduledPeriodID = nil; select("system", manual: false)
    }
    /// Only a newly observed process triggers activation. Existing applications
    /// at startup/wake are a baseline, never permission to restore manual control.
    /// Manual selections (including System) consume and suppress launch events.
    func evaluateApplicationLaunches() {
        let launched = pendingApplicationLaunches; pendingApplicationLaunches.removeAll()
        guard !launched.isEmpty, manualIntent == nil, !isQuitting, !savingCollection,
              machine.state != .fault, machine.state != .restoringSystem,
              simulation || (snapshot != nil && hardwareError == nil && helperHealth == .controlReady) else { return }
        // Profile order breaks ties if multiple programs launch together. A
        // failed/unsupported profile never displaces an available selection.
        guard let profile = profiles.first(where: { profile in
            guard let rule = automation.activationDefaults[profile.id] else { return false }
            return rule.launchWhenOpened && launched.contains(rule.applicationID)
                && runningApplicationIDs.contains(rule.applicationID) && canActivate(profile)
                && activationDefaultUnavailableReason(profile) == nil
        }) else { return }
        select(profile.id, manual: false)
        if machine.selected.id == profile.id { applyActivationDefault(profile, remember: false) }
    }
    func evaluateSchedule() {
        guard manualIntent == nil, !isQuitting, !savingCollection else { return }
        let active = ScheduleEngine.active(in: automation, at: wallClock())
        if blockedScheduleID != active?.id { blockedScheduleID = nil }
        let admitted = active?.id == blockedScheduleID ? nil : active
        let id = admitted?.profileID ?? (defaultResumeBlocked ? "system" : automation.preferences.defaultProfileID)
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        // A persisted profile name is intent, never a lease or permission. A
        // bounded activation default cannot turn into indefinite background control.
        if admitted == nil && profile.kind != .system && automation.activationDefaults[id].map({ $0.kind != .forever }) == true { return }
        if machine.selected.id == id && (machine.state == .system || machine.state == .customActive || machine.state == .initializingCustom) {
            scheduledPeriodID = admitted?.id; return
        }
        guard machine.state != .fault else { return }
        if machine.selected.kind != .system {
            scheduledPeriodID = nil; select("system", manual: false); return
        }
        guard machine.state == .system, simulation || (ownership == .appleObserved && hardwareError == nil),
              simulation || eligibility(profile).allowed, canActivate(profile) else { return }
        scheduledPeriodID = admitted?.id
        select(profile.id, manual: false)
    }
    func automationFailed() {
        pendingApplicationLaunches.removeAll(); defaultResumeBlocked = true
        blockedScheduleID = scheduledPeriodID ?? ScheduleEngine.active(in: automation, at: wallClock())?.id
        clearActivation()
    }
    func resetApplicationLaunchBaseline() {
        observedApplicationInstances = nil; pendingApplicationLaunches.removeAll()
        refreshApplicationAvailability(force: true)
    }
    func reconcileApplicationRules(_ next: AutomationConfiguration) {
        if automation.activationDefaults != next.activationDefaults { resetApplicationLaunchBaseline() }
    }
    func setPreferences(_ update: (inout AppPreferences) -> Void) {
        var next = automation; update(&next.preferences); setAutomation(next, recordHistory: false)
    }
    func setAutomation(_ next: AutomationConfiguration, recordHistory: Bool = true) {
        guard !savingCollection, !isQuitting else { return }
        do {
            try next.validate(profileIDs: Set(profiles.map(\.id)))
            reconcileApplicationRules(next)
            discardFailedConfiguration(); if recordHistory { registerConfigurationUndo() }; automation = next; save(); draftError = nil
        } catch { draftError = error.localizedDescription }
    }
    func removePeriod(_ id: UUID) { var next = automation; next.periods.removeAll { $0.id == id }; setAutomation(next) }
    func removePause(_ id: UUID) { var next = automation; next.pauses.removeAll { $0.id == id }; setAutomation(next) }
    func reviewPeriods(_ periods: [WeeklyPeriod], pauses: [SchedulePause] = [], profiles added: [Profile] = [], replacing: [Profile] = [], defaults: [String: ProfileActivationDefault] = [:]) {
        guard scheduleReview == nil, !savingCollection else { return }
        do {
            var checking = automation
            let incomingIDs = Set(periods.map(\.id))
            let originals = automation.periods.filter { incomingIDs.contains($0.id) }
            checking.periods.removeAll { incomingIDs.contains($0.id) }
            checking.periods += periods; checking.pauses += pauses; checking.activationDefaults.merge(defaults) { _, new in new }
            try checking.validate(profileIDs: Set((profiles + added).map(\.id)), allowConflicts: true)
            scheduleReview = ScheduleReview(remaining: periods, accepted: automation.periods.filter { !incomingIDs.contains($0.id) }, addedProfiles: added, replacements: replacing, originals: originals, pauses: pauses, activationDefaults: defaults)
            advanceReview()
        } catch { draftError = error.localizedDescription }
    }
    func overrideScheduleConflict(_ id: UUID) {
        guard var review = scheduleReview, let incoming = review.remaining.first,
              let incumbent = review.accepted.first(where: { $0.id == id }) else { return }
        let remainder = ScheduleEngine.overriding(incoming, in: [incumbent]).filter { $0.id != incoming.id }
        review.accepted.removeAll { $0.id == id }; review.accepted += remainder
        scheduleReview = review; advanceReview()
    }
    func resolveScheduleConflict(override: Bool, all: Bool = false) {
        guard var review = scheduleReview else { return }
        repeat {
            guard let incoming = review.remaining.first else { break }
            let conflicts = ScheduleEngine.conflicts(incoming, in: review.accepted)
            if conflicts.isEmpty { review.accepted.append(incoming) }
            else if override { review.accepted = ScheduleEngine.overriding(incoming, in: review.accepted) }
            else {
                if let baseline = review.currentBaseline { review.accepted = baseline }
                if let original = review.originals.first(where: { $0.id == incoming.id }) { review.accepted.append(original) }
            }
            review.currentBaseline = nil
            review.remaining.removeFirst()
        } while all && !review.remaining.isEmpty
        scheduleReview = review; advanceReview()
    }
    func advanceReview() {
        guard var review = scheduleReview else { return }
        while let incoming = review.remaining.first {
            if !ScheduleEngine.conflicts(incoming, in: review.accepted).isEmpty {
                if review.currentBaseline == nil { review.currentBaseline = review.accepted }
                scheduleReview = review; return
            }
            review.accepted.append(incoming); review.remaining.removeFirst(); review.currentBaseline = nil
        }
        var next = automation; next.periods = review.accepted; next.pauses += review.pauses; next.activationDefaults.merge(review.activationDefaults) { _, new in new }
        scheduleReview = nil
        let nextProfiles = profiles.map { profile in review.replacements.first { $0.id == profile.id } ?? profile } + review.addedProfiles
        commitConfiguration(profiles: nextProfiles, automation: next, selection: review.addedProfiles.first?.id ?? review.replacements.first?.id ?? editorSelection)
    }
    func importScheduleText(_ text: String) {
        do { let incoming = try ScheduleTextImport.decode(text, profiles: profiles); reviewPeriods(incoming.periods, pauses: incoming.pauses) }
        catch { draftError = error.localizedDescription }
    }
    func exportConfiguration() throws -> Data { try ConfigurationInterchange.encode(.init(profiles: profiles, automation: automation)) }
    func importConfiguration(_ data: Data) {
        guard !savingCollection, !isQuitting else { draftError = "Wait for the current save before replacing settings."; return }
        do {
            let imported = try ConfigurationInterchange.decode(data)
            scheduleReview = nil; defaultResumeBlocked = true; clearActivation(); blockedScheduleID = nil; select("system", manual: false)
            commitConfiguration(profiles: imported.profiles, automation: imported.automation, selection: "system-plus", restore: true)
        } catch { draftError = "Import rejected: \(error.localizedDescription)" }
    }
    func configureLogin() {
        // Diagnostics, tests and SPM binaries must never register as a login application.
        guard Bundle.main.bundleIdentifier == FandyIdentity.appIdentifier, !simulation, !CommandLine.arguments.contains("--functional-check"),
              (try? HelperDiagnosticAction.parse(CommandLine.arguments)) == nil else { return }
        do {
            let service = SMAppService.mainApp
            if automation.preferences.launchAtLogin && service.status == .notRegistered { try service.register() }
            else if !automation.preferences.launchAtLogin && service.status == .enabled { try service.unregister() }
        } catch { draftError = "Login setting could not be applied. Check Login Items in System Settings." }
    }
}
