import SwiftUI
import FandyCore

struct TemperatureTargetEditor: View {
    @Bindable var model: AppModel
    let profile: Profile
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Target temperature", isOn: Binding(get: { profile.targetTemperature != nil }, set: { enabled in
                var next = profile
                if enabled && next.chipSources.isEmpty { next.chipSources = [.cpu, .gpu] }
                next.targetTemperature = enabled ? TemperatureTarget() : nil; model.update(next)
            })).accessibilityIdentifier("profile.target.enabled")
            if let target = profile.targetTemperature {
                HStack {
                    Picker("Sensor", selection: Binding(get: { target.input }, set: { input in
                        var next = profile
                        if input == .chip && next.chipSources.isEmpty { next.chipSources = [.cpu, .gpu] }
                        next.targetTemperature = TemperatureTarget(input: input, celsius: TemperatureTarget.defaultTemperature(for: input)); model.update(next)
                    })) {
                        Text("Chip (hottest)").tag(CurveInput.chip)
                        Text("Trackpad").tag(CurveInput.trackpad)
                        Text("Actuator").tag(CurveInput.actuator)
                        Text("Airflow (hottest)").tag(CurveInput.airflow)
                    }
                    TextField("Temperature", value: Binding(get: { target.celsius }, set: { temperature in
                        var next = profile; next.targetTemperature?.celsius = temperature; model.update(next)
                    }), format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder).frame(width: 60).accessibilityLabel("Target temperature in Celsius")
                    Text("°C")
                    Stepper("Target temperature", value: Binding(get: { target.celsius }, set: { temperature in
                        var next = profile; next.targetTemperature?.celsius = temperature; model.update(next)
                    }), in: 0...125, step: 1).labelsHidden()
                }
                Text("The dashed line in the selected sensor’s graph includes this goal: 50% airflow at the target, rising above it. Curves and chip safety can request more; temperature is not guaranteed.").font(.caption).foregroundStyle(.secondary)
                if let reason = model.eligibility(profile).reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
