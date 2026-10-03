import AppKit
import SwiftUI

struct CurveContextAction {
    let title: String
    let enabled: Bool
    let perform: () -> Void
}
struct CurveContextSurface: NSViewRepresentable {
    let action: (CGPoint) -> CurveContextAction
    func makeNSView(context: Context) -> Surface { let view = Surface(); view.action = action; view.enabled = context.environment.isEnabled; return view }
    func updateNSView(_ view: Surface, context: Context) { view.action = action; view.enabled = context.environment.isEnabled }
    @MainActor final class Surface: NSView {
        var enabled = true
        var action: (CGPoint) -> CurveContextAction = { _ in .init(title: "Add Point", enabled: false, perform: {}) }
        private var pending: CurveContextAction?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard enabled, bounds.contains(point), NSApp.currentEvent?.type == .rightMouseDown else { return nil }; return self
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            let action = action(convert(event.locationInWindow, from: nil)); pending = action
            let menu = NSMenu(); menu.autoenablesItems = false
            let item = NSMenuItem(title: action.title, action: #selector(performAction), keyEquivalent: ""); item.target = self; item.isEnabled = action.enabled
            menu.addItem(item); return menu
        }
        @objc private func performAction() { guard let pending, pending.enabled else { return }; pending.perform(); self.pending = nil }
    }
}
