import SwiftUI
import FandyCore

/// Draft controls do not send commands until the user activates the bounded selection.
struct CustomFanSpeedPicker: View {
    @Bindable var model: AppModel
    let close: () -> Void
    @State private var percent = 30.0
    @State private var duration = 5
    @State private var hours = "0"
    @State private var minutes = "5"
    @State private var error: String?
    private let presets = [5, 10, 15, 30, 60, 120, 240, 360, 720, 1440]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Fan speed")
                Spacer()
                Text("\(Int(percent))%").monospacedDigit().bold()
            }
            Slider(value: $percent, in: 0...100, step: 1)
                .accessibilityLabel("Temporary fan speed")
            Picker("For", selection: $duration) {
                ForEach(presets, id: \.self) { value in
                    Text(value < 60 ? "\(value) minutes" : "\(value / 60) \(value == 60 ? "hour" : "hours")").tag(value)
                }
                Text("Other…").tag(0)
            }
            if duration == 0 {
                HStack(spacing: 6) {
                    TextField("Hours", text: $hours).textFieldStyle(.roundedBorder).frame(width: 45)
                    Text("h")
                    TextField("Minutes", text: $minutes).textFieldStyle(.roundedBorder).frame(width: 45)
                    Text("min")
                }
            }
            Text("0% is the fan’s minimum speed.")
                .font(.caption).foregroundStyle(.secondary)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Activate") { apply() }
                .buttonStyle(.bordered).disabled(!model.canActivateCustomFanSpeed)
        }.padding(10).frame(width: 220)
        .onAppear {
            percent = model.isCustomFanSpeedActive ? model.machine.selected.floor :
                (model.snapshot?.fans.compactMap { try? $0.percent(rpm: $0.actualRPM) }.max() ?? 30)
        }
    }
    private func apply() {
        let seconds: Double
        if duration == 0 {
            func integer(_ value: String) -> Int? {
                guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
                return Int(value)
            }
            guard let h = integer(hours), let m = integer(minutes), (0...744).contains(h), (0...59).contains(m) else {
                error = "Enter a valid hour and minute."; return
            }
            seconds = Double(h) * 3600 + Double(m) * 60
        } else { seconds = Double(duration) * 60 }
        if model.activateCustomFanSpeed(percent: percent, seconds: seconds) { close() }
        else { error = model.draftError }
    }
}
