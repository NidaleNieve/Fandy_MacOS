import SwiftUI
import AppKit
import FandyCore

struct ScheduleEditor: View {
    @Bindable var model: AppModel
    let profile: Profile
    @State private var day = 1
    @State private var start = "08:30"
    @State private var end = "16:30"
    @State private var pauseStart = Date()
    @State private var pauseEnd = Date().addingTimeInterval(86400)
    @State private var importing = false
    @State private var editing: WeeklyPeriod?
    var body: some View {
        DisclosureGroup("Schedule") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Manual selections take priority. Resume Schedule in the menu to return to automation.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(1...7, id: \.self) { weekday in
                    let rows = dayRows(weekday)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ScheduleTextImport.days[weekday - 1]).font(.subheadline).bold()
                        if rows.isEmpty { Text("No scheduled activation").font(.caption).foregroundStyle(.secondary) }
                        ForEach(rows, id: \.id) { row in
                            HStack {
                                Toggle("\(ScheduleEngine.time(row.start))–\(ScheduleEngine.time(row.end))\(row.spill ? " · from previous day" : "")", isOn: Binding(get: { row.period.enabled }, set: { value in
                                    var incoming = row.period; incoming.enabled = value
                                    if value { model.reviewPeriods([incoming]) }
                                    else { var config = model.automation; if let index = config.periods.firstIndex(where: { $0.id == incoming.id }) { config.periods[index] = incoming }; model.setAutomation(config) }
                                }))
                                Spacer()
                                Button("Edit") { editing = row.period }.buttonStyle(.borderless)
                                Button { model.removePeriod(row.period.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove entire time range")
                            }.font(.caption)
                        }
                    }
                }
                HStack {
                    Picker("Day", selection: $day) { ForEach(1...7, id: \.self) { Text(ScheduleTextImport.days[$0 - 1]).tag($0) } }.labelsHidden().frame(width: 130)
                    TextField("Start HH:mm", text: $start).frame(width: 70)
                    Text("–")
                    TextField("End HH:mm", text: $end).frame(width: 70)
                    Button("Add") { add() }
                }
                Text("24-hour times. An earlier end spills into the next day; 24:00 ends at midnight.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Pauses").font(.subheadline).bold()
                ForEach(model.automation.pauses.filter { $0.profileID == profile.id || $0.profileID == nil }) { pause in
                    HStack {
                        Text("\(pause.start.formatted(date: .abbreviated, time: .shortened)) – \(pause.end.formatted(date: .abbreviated, time: .shortened))\(pause.profileID == nil ? " · all profiles" : "")").font(.caption)
                        Spacer()
                        Button { model.removePause(pause.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                DatePicker("From", selection: $pauseStart).environment(\.locale, Locale(identifier: model.automation.preferences.use24HourTime ? "en_GB" : "en_US"))
                DatePicker("Until", selection: $pauseEnd).environment(\.locale, Locale(identifier: model.automation.preferences.use24HourTime ? "en_GB" : "en_US"))
                HStack {
                    Button("Add Pause") {
                        var next = model.automation; next.pauses.append(SchedulePause(profileID: profile.id, start: pauseStart, end: pauseEnd)); model.setAutomation(next)
                    }
                    Spacer()
                    Button("Import Schedule from Text…") { importing = true }
                }
            }.padding(.top, 8)
        }.accessibilityIdentifier("profile.schedule")
        .sheet(isPresented: $importing) { ScheduleTextSheet(model: model) }
        .sheet(item: $editing) { period in WeeklyPeriodEditor(model: model, period: period) }
    }
    private struct Row {
        let period: WeeklyPeriod; let start: Int; let end: Int; let spill: Bool
        var id: String { "\(period.id):\(start):\(spill)" }
    }
    private func dayRows(_ day: Int) -> [Row] {
        let dayStart = (day - 1) * 1440, dayEnd = day * 1440
        return model.automation.periods.filter { $0.profileID == profile.id }.flatMap { period in
            period.segments.compactMap { segment in
                guard let clipped = segment.intersection(WeekSegment(start: dayStart, end: dayEnd)) else { return nil }
                return Row(period: period, start: clipped.start - dayStart, end: clipped.end - dayStart, spill: period.weekday != day)
            }
        }.sorted { $0.start < $1.start }
    }
    private func add() {
        do {
            let period = try WeeklyPeriod(profileID: profile.id, weekday: day, startMinute: ScheduleEngine.parseTime(start), endMinute: ScheduleEngine.parseTime(end, allowEndOfDay: true))
            model.reviewPeriods([period])
        } catch { model.draftError = error.localizedDescription }
    }
}
struct WeeklyPeriodEditor: View {
    @Bindable var model: AppModel
    let period: WeeklyPeriod
    @Environment(\.dismiss) private var dismiss
    @State private var day: Int
    @State private var start: String
    @State private var end: String
    @State private var error: String?
    init(model: AppModel, period: WeeklyPeriod) {
        self.model = model; self.period = period
        _day = State(initialValue: period.weekday)
        _start = State(initialValue: ScheduleEngine.time(period.startMinute))
        _end = State(initialValue: ScheduleEngine.time(period.endMinute))
    }
    var body: some View {
        Form {
            Picker("Day", selection: $day) { ForEach(1...7, id: \.self) { Text(ScheduleTextImport.days[$0 - 1]).tag($0) } }
            TextField("Start HH:mm", text: $start)
            TextField("End HH:mm", text: $end)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }; Spacer()
                Button("Save") {
                    do {
                        var next = period; next.weekday = day
                        next.startMinute = try ScheduleEngine.parseTime(start)
                        next.endMinute = try ScheduleEngine.parseTime(end, allowEndOfDay: true)
                        try next.validate(profileIDs: Set(model.profiles.map(\.id)))
                        dismiss()
                        Task { @MainActor in await Task.yield(); model.reviewPeriods([next]) }
                    } catch { self.error = error.localizedDescription }
                }
            }
        }.padding(20).frame(width: 350, height: 220)
    }
}
struct ScheduleTextSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Schedule from Text").font(.headline)
            Text("Copy the format prompt into your chatbot, add your schedule, then paste its JSON here. Fandy does not contact the chatbot.").font(.caption)
            Button("Copy Chatbot Prompt") { copy(ScheduleTextImport.prompt(profiles: model.profiles)) }
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 200)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                Button("Copy Errors") { copy(error) }
            }
            HStack {
                Button("Cancel") { dismiss() }; Spacer()
                Button("Review Import") {
                    do {
                        let incoming = try ScheduleTextImport.decode(text, profiles: model.profiles)
                        var config = model.automation; config.periods += incoming.periods; config.pauses += incoming.pauses
                        try config.validate(profileIDs: Set(model.profiles.map(\.id)), allowConflicts: true)
                        // Dismiss the text sheet before presenting the shared conflict sheet.
                        dismiss()
                        Task { @MainActor in
                            await Task.yield(); model.reviewPeriods(incoming.periods, pauses: incoming.pauses)
                        }
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 580, height: 420)
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}
struct ScheduleConflictSheet: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule Conflicts").font(.headline)
            if let review = model.scheduleReview, let incoming = review.remaining.first {
                Text("Adding \(name(incoming.profileID)) · \(ScheduleTextImport.days[incoming.weekday - 1]) \(ScheduleEngine.time(incoming.startMinute))–\(ScheduleEngine.time(incoming.endMinute))")
                Text("Override shortens the existing range. Skip leaves it unchanged and skips this incoming range.").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    ForEach(review.conflict) { conflict in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(name(conflict.incumbent.profileID)) currently takes priority").bold()
                            ForEach(Array(conflict.overlaps.enumerated()), id: \.offset) { _, segment in
                                Text(overlapDescription(segment)).font(.caption)
                            }
                            HStack {
                                Button("Skip") { model.resolveScheduleConflict(override: false) }
                                Button("Override") { model.overrideScheduleConflict(conflict.id) }
                            }
                        }.padding(.vertical, 8)
                        Divider()
                    }
                }
                HStack {
                    Button("Cancel Import") { model.scheduleReview = nil }
                    Spacer()
                    Button("Skip All") { model.resolveScheduleConflict(override: false, all: true) }
                    Button("Override All") { model.resolveScheduleConflict(override: true, all: true) }
                }
            }
        }.padding(20).frame(width: 540, height: 400)
    }
    private func overlapDescription(_ segment: WeekSegment) -> String {
        let firstDay = segment.start / 1440, lastDay = (segment.end - 1) / 1440
        let endTime = segment.end % 1440 == 0 ? "24:00" : ScheduleEngine.time(segment.end % 1440)
        let endDay = firstDay == lastDay ? "" : ScheduleTextImport.days[lastDay] + " "
        return "\(ScheduleTextImport.days[firstDay]) · \(ScheduleEngine.time(segment.start % 1440))–\(endDay)\(endTime)"
    }
    private func name(_ id: String) -> String {
        (model.profiles + (model.scheduleReview?.addedProfiles ?? [])).first { $0.id == id }?.name ?? "Profile"
    }
}
