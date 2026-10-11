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
