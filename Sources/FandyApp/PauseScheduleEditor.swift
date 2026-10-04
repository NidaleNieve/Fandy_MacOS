import SwiftUI
import FandyCore

struct PauseScheduleEditor: View {
    @Bindable var model: AppModel
    let profile: Profile
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(86400)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.automation.pauses.filter { $0.profileID == profile.id || $0.profileID == nil }) { pause in
                HStack {
                    Text("\(pause.start.formatted(date: .abbreviated, time: .shortened)) – \(pause.end.formatted(date: .abbreviated, time: .shortened))\(pause.profileID == nil ? " · all profiles" : "")").font(.caption)
                    Spacer()
                    Button { model.removePause(pause.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Remove pause")
                }
            }
            DatePicker("From", selection: $start)
            DatePicker("Until", selection: $end)
            Button("Add Pause") {
                var next = model.automation
                next.pauses.append(SchedulePause(profileID: profile.id, start: start, end: end))
                model.setAutomation(next)
            }
            Divider()
            Label("Pauses suspend this profile’s scheduled activations, including overnight ranges. Manual selections still take priority.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.environment(\.locale, Locale(identifier: model.automation.preferences.use24HourTime ? "en_GB" : "en_US"))
            .accessibilityIdentifier("profile.pauses")
    }
}
