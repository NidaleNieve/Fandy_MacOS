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
                            if rows.isEmpty { Text("System").font(.caption).foregroundStyle(.secondary) }
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
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
            Divider()
            Label("Unscheduled time uses System. Manual selections and application activations take priority; pause ranges suspend schedules.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(width: 540, height: 580)
    }
}
