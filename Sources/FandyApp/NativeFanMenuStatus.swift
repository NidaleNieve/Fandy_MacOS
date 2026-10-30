import AppKit
import Observation
import FandyCore

/// The frequently opened menu does not need to initialize SwiftUI's scene graph.
/// Editor readouts keep their existing SwiftUI presentation.
@MainActor final class NativeFanMenuStatus: NSView {
    private let model: AppModel
    private let stack = NSStackView()
    private(set) var readingText = ""
    private var last: Presentation?
    private struct Reading: Equatable { let name: String; let value: String }
    private struct Presentation: Equatable {
        let bar: Double?
        let numbers: String?
        let unavailable: Bool
        let status: String
        let readings: [Reading]
    }
    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: 30))
        autoresizingMask = [.width]
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5)
        ])
        observe()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private func observe() {
        withObservationTracking { refresh() } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
    private func refresh() {
        let preferences = model.automation.preferences
        let fans = model.snapshot?.fans ?? []
        let available = !fans.isEmpty && model.ownership != .unknown
        let percentage = StatusPresentation.observedFanPercent(fans)
        let numbers = "\(Int(percentage.rounded()))% · " + fans.map { "\(Int($0.actualRPM.rounded()))" }.joined(separator: " / ") + " RPM"
        let next = Presentation(bar: available && preferences.showFanSpeedBar ? percentage : nil,
            numbers: available && preferences.showFanSpeedNumbers ? numbers : nil,
            unavailable: !available && (preferences.showFanSpeedBar || preferences.showFanSpeedNumbers),
            status: model.statusText, readings: preferences.menuSensors.map {
                Reading(name: MenuTemperatureReadout.compact(model.sensorMenu.title(for: $0)),
                    value: MenuTemperatureReadout.temperature(model.sensorMenu.valueText(for: $0)))
            })
        guard next != last else { return }; last = next
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
        var text: [String] = []
        if let percentage = next.bar {
            let bar = FanLevelBar(percentage: percentage)
            bar.setAccessibilityElement(true); bar.setAccessibilityRole(.levelIndicator)
            bar.setAccessibilityLabel("Observed fan speed"); bar.setAccessibilityValue("\(Int(percentage.rounded())) percent")
            stack.addArrangedSubview(bar)
            bar.widthAnchor.constraint(equalToConstant: 120).isActive = true
            bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
        }
        if let numbers = next.numbers {
            let label = label(numbers); label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            stack.addArrangedSubview(label); text.append(numbers)
        }
        if next.unavailable { stack.addArrangedSubview(label("Fan speed unavailable", secondary: true)); text.append("Fan speed unavailable") }
        let status = NSTextField(wrappingLabelWithString: next.status)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.alignment = .center
        status.preferredMaxLayoutWidth = MenuLayout.textWidth
        status.widthAnchor.constraint(equalToConstant: MenuLayout.textWidth).isActive = true
        stack.addArrangedSubview(status); text.append(next.status)
        for reading in next.readings {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
            let name = label(reading.name, secondary: true), value = label(reading.value)
            name.lineBreakMode = .byTruncatingTail; name.alignment = .left
            value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold); value.alignment = .right
            row.addArrangedSubview(name); row.addArrangedSubview(value)
            name.widthAnchor.constraint(equalToConstant: 112).isActive = true
            value.widthAnchor.constraint(equalToConstant: MenuTemperatureReadout.valueWidth).isActive = true
            row.toolTip = reading.name + ": " + reading.value
            stack.addArrangedSubview(row); text.append(row.toolTip!)
        }
        readingText = text.joined(separator: "\n")
        layoutSubtreeIfNeeded()
        frame.size.height = ceil(stack.fittingSize.height) + 10
    }
    private func label(_ text: String, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11); field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.alignment = .center; field.lineBreakMode = .byClipping
        return field
    }
}

@MainActor private final class FanLevelBar: NSView {
    let percentage: Double
    init(percentage: Double) { self.percentage = percentage; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: bounds.width * percentage / 100, height: bounds.height), xRadius: 1.5, yRadius: 1.5).fill()
    }
}
