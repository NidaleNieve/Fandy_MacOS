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
    func applyActivationDefault(_ profile: Profile) {
        manualIntent = ActivationIntent(profileID: profile.id); activationDeadline = nil; watchedProcessName = nil; scheduledPeriodID = nil; blockedScheduleID = nil
        guard let rule = automation.activationDefaults[profile.id] else { return }
        switch rule.kind {
        case .forever: break
        case .duration: activateFor(seconds: Double(rule.seconds))
        case .application:
            if let process = applicationCatalog().first(where: { $0.bundleID == rule.applicationID }) { activateWhile(process) }
            else { clearActivation(); select("system", manual: false) }
        }
    }
    func setActivationDefault(_ rule: ProfileActivationDefault, profileID: String) {
        var next = automation; next.activationDefaults[profileID] = rule; setAutomation(next)
        if rule.kind == .application { refreshApplicationAvailability(force: true) }
    }
    var cancellationTitle: String {
        guard let intent = manualIntent else { return scheduledPeriodID == nil ? "Resume Schedule" : "Cancel \(machine.selected.name)" }
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
        return "Schedule ready · System"
    }
    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = automation.preferences.use24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
    func activateForever() { _ = claimCurrentActivation(.forever) }
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
        manualIntent = ActivationIntent(profileID: profile.id, limit: limit)
        activationDeadline = nil; watchedProcessName = nil; scheduledPeriodID = nil; blockedScheduleID = nil
        return true
    }
    func cancelActivation() {
        if manualIntent == nil, let occurrence = scheduledPeriodID {
            clearActivation(); blockedScheduleID = occurrence; select("system", manual: false)
        } else { resumeSchedule() }
    }
    func resumeSchedule() {
        clearActivation(); blockedScheduleID = nil
        select("system", manual: false)
    }
    func clearActivation() {
        manualIntent = nil; activationDeadline = nil; watchedProcessName = nil; scheduledPeriodID = nil
    }
    /// Called before sampling/commands. A delayed tick cannot renew an expired activation.
    func expireActivation() {
        guard let intent = manualIntent else { return }
        let expired = (activationDeadline.map { clockNow() >= $0 } ?? false) || intent.expired(at: wallClock(), running: ProcessCatalog.isRunning)
        if expired { clearActivation(); select("system", manual: false) }
    }
    func expireScheduledOccurrence() {
        guard manualIntent == nil, let scheduledPeriodID,
              ScheduleEngine.active(in: automation, at: wallClock())?.id != scheduledPeriodID else { return }
        self.scheduledPeriodID = nil; select("system", manual: false)
    }
    func evaluateSchedule() {
        guard manualIntent == nil, !isQuitting, !savingCollection else { return }
        let active = ScheduleEngine.active(in: automation, at: wallClock())
        if blockedScheduleID != active?.id { blockedScheduleID = nil }
        guard active?.id != blockedScheduleID || active == nil else { return }
        if scheduledPeriodID == active?.id { return }
        // Handback is acknowledged before any scheduled lease is admitted.
        if machine.selected.kind != .system {
            scheduledPeriodID = nil; select("system", manual: false); return
        }
        guard machine.state == .system, simulation || ownership == .appleObserved else { return }
        guard let active, let profile = profiles.first(where: { $0.id == active.profileID }), (simulation || eligibility(profile).allowed) else { return }
        scheduledPeriodID = active.id
        select(profile.id, manual: false)
    }
    func automationFailed() {
        blockedScheduleID = scheduledPeriodID ?? ScheduleEngine.active(in: automation, at: wallClock())?.id
        clearActivation()
    }
    func setPreferences(_ update: (inout AppPreferences) -> Void) {
        var next = automation; update(&next.preferences); setAutomation(next, recordHistory: false)
    }
    func setAutomation(_ next: AutomationConfiguration, recordHistory: Bool = true) {
        guard !savingCollection, !isQuitting else { return }
        do {
            try next.validate(profileIDs: Set(profiles.map(\.id)))
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
            scheduleReview = nil; clearActivation(); blockedScheduleID = nil; select("system", manual: false)
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
