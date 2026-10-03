import AppKit

/// NSMenu's standard titles do not wrap. Use a bounded native view only for
/// unusually long actions; ordinary rows retain all of AppKit's native behavior.
@MainActor final class BoundedMenuAction: NSView {
    private let title: String
    private var hovered = false
    private var tracking: NSTrackingArea?
    private let paragraph: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping; return style
    }()
    private var attributes: [NSAttributedString.Key: Any] { [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: paragraph] }
    override var isFlipped: Bool { true }
    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        let height = (title as NSString).boundingRect(with: NSSize(width: MenuLayout.nativeTitleWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: attributes).height
        frame.size = NSSize(width: MenuLayout.width, height: max(24, ceil(height) + 8))
        setAccessibilityElement(true); setAccessibilityRole(.menuItem); setAccessibilityLabel(title)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hovered = false; needsDisplay = true }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let enabled = enclosingMenuItem?.isEnabled ?? false
        let highlighted = enabled && (hovered || enclosingMenuItem?.isHighlighted == true)
        if highlighted { NSColor.selectedContentBackgroundColor.setFill(); bounds.fill() }
        let color = !enabled ? NSColor.disabledControlTextColor : highlighted ? NSColor.selectedMenuItemTextColor : NSColor.controlTextColor
        var attrs = attributes; attrs[.foregroundColor] = color
        (title as NSString).draw(with: NSRect(x: 28, y: 4, width: MenuLayout.nativeTitleWidth, height: bounds.height - 8), options: .usesLineFragmentOrigin, attributes: attrs)
        if enclosingMenuItem?.state == .on {
            let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [color]))
            image?.draw(in: NSRect(x: 9, y: 6, width: 12, height: 12))
        }
    }
    override func mouseUp(with event: NSEvent) { performAction() }
    override func accessibilityPerformPress() -> Bool { performAction() }
    @discardableResult private func performAction() -> Bool {
        guard let item = enclosingMenuItem, item.isEnabled, let action = item.action else { return false }
        item.menu?.cancelTracking()
        return NSApp.sendAction(action, to: item.target, from: item)
    }
}
