import SwiftUI
import FandyCore

/// Shared projection also used by tests: overnight entries appear on both days,
/// including Sunday-to-Monday, with each portion clipped to that day's bounds.
struct ScheduleOverviewRow: Identifiable, Equatable {
    let periodID: UUID
    let profileID: String
    let start: Int
    let end: Int
    let continued: Bool
    var id: String { "\(periodID):\(start):\(continued)" }
    static func rows(day: Int, periods: [WeeklyPeriod]) -> [Self] {
        guard (1...7).contains(day) else { return [] }
        let bounds = WeekSegment(start: (day - 1) * 1440, end: day * 1440)
        let rows: [Self] = periods.filter(\.enabled).flatMap { period -> [Self] in
            period.segments.compactMap { segment -> Self? in
                guard let overlap = segment.intersection(bounds) else { return nil }
                return Self(periodID: period.id, profileID: period.profileID,
                            start: overlap.start - bounds.start, end: overlap.end - bounds.start,
                            continued: period.weekday != day)
            }
        }
        return rows.sorted { $0.start == $1.start ? $0.profileID < $1.profileID : $0.start < $1.start }
    }
}
struct WeeklyScheduleOverview: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Weekly Schedule").font(.headline); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(1...7, id: \.self) { day in
                        let rows = ScheduleOverviewRow.rows(day: day, periods: model.automation.periods)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ScheduleTextImport.days[day - 1]).font(.subheadline).bold()
                            ForEach(rows) { row in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(ScheduleEngine.time(row.start))–\(ScheduleEngine.time(row.end))").monospacedDigit().frame(width: 100, alignment: .leading)
                                    Text(model.profiles.first { $0.id == row.profileID }?.name ?? "Unavailable profile")
                                    if row.continued { Text("from previous day").foregroundStyle(.secondary).font(.caption) }
                                    Spacer(minLength: 0)
                                }.font(.callout)
                            }
                        }
                    }
                    if !model.automation.pauses.isEmpty {
                        Divider(); Text("Schedule Pauses").font(.subheadline).bold()
                        ForEach(model.automation.pauses.sorted { $0.start < $1.start }) { pause in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pause.profileID.flatMap { id in model.profiles.first { $0.id == id }?.name } ?? "All profiles")
                                Text("\(pause.start.formatted(date: .abbreviated, time: .shortened)) – \(pause.end.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    let conditions = ProfileConditionOverviewRow.rows(profiles: model.profiles, automation: model.automation)
                    if !conditions.isEmpty {
                        Divider(); Text("Activation Conditions").font(.subheadline).bold()
                        ForEach(conditions) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.profileName).font(.callout)
                                if let trigger = row.trigger { Text(trigger).font(.caption).foregroundStyle(.secondary) }
                                Text(row.limit).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if model.manualIntent != nil {
                        Divider(); Text("Current Override").font(.subheadline).bold()
                        Text(model.machine.selected.name + " · " + model.activationDescription).font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
            Divider()
            Label("Between scheduled periods, your remembered default profile stays active. Temporary overrides take priority; pause ranges suspend schedules.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(width: 540, height: 580)
    }
}

/// Only configured rules appear here; an ordinary unlimited profile is not a schedule.
struct ProfileConditionOverviewRow: Identifiable, Equatable {
    let id: String
    let profileName: String
    let trigger: String?
    let limit: String
    static func rows(profiles: [Profile], automation: AutomationConfiguration) -> [Self] {
        profiles.compactMap { profile in
            guard let rule = automation.activationDefaults[profile.id], rule.launchWhenOpened || rule.kind != .forever else { return nil }
            let app = rule.applicationName.isEmpty ? rule.applicationID : rule.applicationName
            let limit: String
            switch rule.kind {
            case .forever: limit = "Until changed"
            case .application: limit = "Until \(app) closes"
            case .duration:
                let hours = rule.seconds / 3600, minutes = (rule.seconds % 3600) / 60, seconds = rule.seconds % 60
                limit = "For " + [hours > 0 ? "\(hours) hr" : nil, minutes > 0 ? "\(minutes) min" : nil, seconds > 0 ? "\(seconds) sec" : nil].compactMap { $0 }.joined(separator: " ")
            }
            return Self(id: profile.id, profileName: profile.name, trigger: rule.launchWhenOpened ? "When \(app) opens" : nil, limit: limit)
        }
    }
}
