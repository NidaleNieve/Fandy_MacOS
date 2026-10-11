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

/// Native controls receive menu-window events directly. Opening this view never
/// activates cooling; user edits apply on the existing bounded control path.
@MainActor final class CustomFanSpeedMenuView: NSView, NSTextFieldDelegate {
    let slider = MenuFanSpeedSlider()
    let durationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let model: AppModel
    private let percentage = NSTextField(labelWithString: "")
    private let hours = NSTextField(string: "0")
    private let minutes = NSTextField(string: "5")
    private let error = NSTextField(wrappingLabelWithString: "")
    private var customFields: [NSView] = []
    private static let presets = [5, 10, 15, 30, 60, 120, 240, 360, 720, 1440]
    override var isFlipped: Bool { true }

    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 98))
        label("Fan speed", at: NSRect(x: 10, y: 10, width: 145, height: 18))
        percentage.frame = NSRect(x: 170, y: 10, width: 60, height: 18)
        percentage.alignment = .right
        percentage.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        addSubview(percentage)
        slider.frame = NSRect(x: 10, y: 34, width: 220, height: 22)
        slider.minValue = 0; slider.maxValue = 100; slider.numberOfTickMarks = 0
        slider.isContinuous = true; slider.target = self; slider.action = #selector(speedChanged)
        slider.setAccessibilityLabel("Temporary fan speed")
        slider.doubleValue = model.isCustomFanSpeedActive ? model.machine.selected.floor :
            (model.snapshot?.fans.compactMap { try? $0.percent(rpm: $0.actualRPM) }.max() ?? 30)
        percentage.stringValue = "\(Int(slider.doubleValue.rounded()))%"
        slider.isEnabled = model.canActivateCustomFanSpeed
        addSubview(slider)
        label("For", at: NSRect(x: 10, y: 68, width: 30, height: 18))
        durationPopup.frame = NSRect(x: 45, y: 63, width: 185, height: 26)
        durationPopup.controlSize = .small
        durationPopup.menu?.autoenablesItems = false
        for value in Self.presets {
            durationPopup.addItem(withTitle: value < 60 ? "\(value) minutes" : "\(value / 60) \(value == 60 ? "hour" : "hours")")
            durationPopup.lastItem?.tag = value
        }
        durationPopup.addItem(withTitle: "Other…"); durationPopup.lastItem?.tag = 0
        durationPopup.selectItem(withTag: 5)
        // Reopening preserves the current deadline; this is a readout, not a reset.
        if model.isCustomFanSpeedActive, let deadline = model.activationDeadline {
            let remaining = max(1, Int(ceil((deadline - model.clockNow()) / 60)))
            if !Self.presets.contains(remaining) {
                durationPopup.insertItem(withTitle: "\(remaining) minutes remaining", at: 0)
                durationPopup.item(at: 0)?.tag = remaining
            }
            durationPopup.selectItem(withTag: remaining)
        }
        durationPopup.target = self; durationPopup.action = #selector(durationChanged)
        durationPopup.setAccessibilityLabel("Temporary fan speed duration")
        addSubview(durationPopup)
        hours.frame = NSRect(x: 35, y: 99, width: 50, height: 24)
        minutes.frame = NSRect(x: 128, y: 99, width: 50, height: 24)
        for field in [hours, minutes] {
            field.alignment = .center; field.delegate = self; field.bezelStyle = .roundedBezel
            field.font = .systemFont(ofSize: 13); addSubview(field)
        }
        hours.setAccessibilityLabel("Hours"); minutes.setAccessibilityLabel("Minutes")
        customFields = [hours, minutes,
            label("h", at: NSRect(x: 90, y: 102, width: 24, height: 18)),
            label("min", at: NSRect(x: 183, y: 102, width: 30, height: 18))]
        error.textColor = .systemRed; error.font = .systemFont(ofSize: 11)
        addSubview(error)
        updateLayout()
    }
    required init?(coder: NSCoder) { nil }
    @discardableResult private func label(_ title: String, at frame: NSRect) -> NSTextField {
        let view = NSTextField(labelWithString: title); view.frame = frame; addSubview(view); return view
    }
    @objc private func speedChanged() {
        let value = slider.doubleValue.rounded()
        percentage.stringValue = "\(Int(value))%"
        let seconds = selectedSeconds()
        guard model.isCustomFanSpeedActive || seconds != nil else { showError("Enter a positive duration up to 31 days."); return }
        if model.updateCustomFanSpeed(percent: value, initialSeconds: seconds ?? 300) {
            showError(seconds == nil ? "Enter a positive duration up to 31 days." : nil)
        }
        else { showError(model.draftError) }
    }
    @objc private func durationChanged() {
        updateLayout()
        // Opening the custom fields is not a completed duration selection.
        if durationPopup.selectedItem?.tag == 0 { showError(nil); return }
        applyDuration()
    }
    func controlTextDidChange(_ notification: Notification) { applyDuration() }
    private func applyDuration() {
        guard let seconds = selectedSeconds() else { showError("Enter a positive duration up to 31 days."); return }
        if model.isCustomFanSpeedActive { model.activateFor(seconds: seconds) }
        showError(nil)
    }
    private func selectedSeconds() -> Double? {
        if let tag = durationPopup.selectedItem?.tag, tag > 0 { return Double(tag) * 60 }
        func integer(_ field: NSTextField) -> Int? {
            let value = field.stringValue
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(value)
        }
        guard let h = integer(hours), let m = integer(minutes), (0...744).contains(h), (0...59).contains(m) else { return nil }
        let seconds = Double(h) * 3600 + Double(m) * 60
        return seconds > 0 && seconds <= 31 * 86400 ? seconds : nil
    }
    private func showError(_ message: String?) {
        error.stringValue = message ?? ""; updateLayout()
    }
    private func updateLayout() {
        let custom = durationPopup.selectedItem?.tag == 0
        customFields.forEach { $0.isHidden = !custom }
        let base: CGFloat = custom ? 133 : 98
        error.isHidden = error.stringValue.isEmpty
        error.frame = NSRect(x: 10, y: base, width: 220, height: 32)
        let size = NSSize(width: 240, height: base + (error.isHidden ? 0 : 38))
        guard frame.size != size else { return }
        setFrameSize(size)
        enclosingMenuItem?.menu?.update()
    }
}
