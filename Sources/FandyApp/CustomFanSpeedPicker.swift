import AppKit
import FandyCore

/// AppKit owns the complete drag, including excursions outside the menu. A
/// SwiftUI gesture would otherwise yield those events back to menu tracking.
@MainActor final class MenuFanSpeedSlider: NSSlider {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let cell else { return }
        _ = cell.trackMouse(with: event, in: bounds, of: self, untilMouseUp: true)
    }
}

/// Slider events stay in the menu window. Duration choices live in ordinary
/// NSMenu submenus, so no popup has to open inside another tracking menu.
@MainActor final class CustomFanSpeedMenuView: NSView {
    let slider = MenuFanSpeedSlider()
    private let model: AppModel
    private let percentage = NSTextField(labelWithString: "")
    private let error = NSTextField(wrappingLabelWithString: "")
    override var isFlipped: Bool { true }
    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 64))
        let title = NSTextField(labelWithString: "Fan speed")
        title.frame = NSRect(x: 10, y: 10, width: 145, height: 18); addSubview(title)
        percentage.frame = NSRect(x: 170, y: 10, width: 60, height: 18)
        percentage.alignment = .right; percentage.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        addSubview(percentage)
        slider.frame = NSRect(x: 10, y: 34, width: 220, height: 22)
        slider.minValue = 0; slider.maxValue = 100; slider.numberOfTickMarks = 0
        slider.isContinuous = true; slider.target = self; slider.action = #selector(speedChanged)
        slider.setAccessibilityLabel("Temporary fan speed")
        slider.doubleValue = model.isCustomFanSpeedActive ? model.machine.selected.floor :
            (model.snapshot?.fans.compactMap { try? $0.percent(rpm: $0.actualRPM) }.max() ?? 30)
        percentage.stringValue = "\(Int(slider.doubleValue.rounded()))%"
        slider.isEnabled = model.canActivateCustomFanSpeed; addSubview(slider)
        error.textColor = .systemRed; error.font = .systemFont(ofSize: 11)
        error.frame = NSRect(x: 10, y: 64, width: 220, height: 32); error.isHidden = true; addSubview(error)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func speedChanged() {
        let value = slider.doubleValue.rounded()
        percentage.stringValue = "\(Int(value))%"
        let accepted = model.updateCustomFanSpeed(percent: value)
        error.stringValue = accepted ? "" : model.draftError ?? "Fan control is unavailable."
        error.isHidden = accepted
        let size = NSSize(width: 240, height: accepted ? 64 : 102)
        if frame.size != size { setFrameSize(size); enclosingMenuItem?.menu?.update() }
    }
}

/// Custom hours/minutes remember only completed, valid durations. Merely opening
/// this submenu does not retime or activate the current selection.
@MainActor final class CustomFanSpeedDurationView: NSView, NSTextFieldDelegate {
    private let model: AppModel
    private let hours = NSTextField()
    private let minutes = NSTextField()
    private let error = NSTextField(wrappingLabelWithString: "")
    override var isFlipped: Bool { true }
    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 52))
        let chosen = model.automation.preferences.customFanSpeedDurationMinutes
        hours.stringValue = "\(chosen / 60)"; minutes.stringValue = "\(chosen % 60)"
        hours.frame = NSRect(x: 25, y: 13, width: 50, height: 24)
        minutes.frame = NSRect(x: 120, y: 13, width: 50, height: 24)
        for field in [hours, minutes] {
            field.alignment = .center; field.delegate = self; field.bezelStyle = .roundedBezel
            field.font = .systemFont(ofSize: 13); addSubview(field)
        }
        hours.setAccessibilityLabel("Hours"); minutes.setAccessibilityLabel("Minutes")
        for (title, x) in [("h", 80.0), ("min", 175.0)] {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: x, y: 16, width: 35, height: 18); addSubview(label)
        }
        error.textColor = .systemRed; error.font = .systemFont(ofSize: 11)
        error.frame = NSRect(x: 10, y: 52, width: 220, height: 32); error.isHidden = true; addSubview(error)
    }
    required init?(coder: NSCoder) { nil }
    static func durationLabel(_ value: Int) -> String {
        let h = value / 60, m = value % 60
        let hour = "\(h) \(h == 1 ? "hour" : "hours")"
        let minute = "\(m) \(m == 1 ? "minute" : "minutes")"
        if h == 0 { return minute }
        if m == 0 { return hour }
        return hour + " " + minute
    }
    func controlTextDidChange(_ notification: Notification) {
        func integer(_ field: NSTextField) -> Int? {
            let value = field.stringValue
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(value)
        }
        let accepted: Bool
        if let h = integer(hours), let m = integer(minutes), (0...744).contains(h), (0...59).contains(m) {
            accepted = model.setCustomFanSpeedDuration(minutes: h * 60 + m)
        } else { accepted = false }
        error.stringValue = accepted ? "" : "Enter a positive duration up to 31 days."
        error.isHidden = accepted
        let size = NSSize(width: 240, height: accepted ? 52 : 90)
        if frame.size != size { setFrameSize(size); enclosingMenuItem?.menu?.update() }
    }
}
