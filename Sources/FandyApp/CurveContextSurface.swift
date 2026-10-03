import AppKit
import SwiftUI

struct CurveContextAction {
    let enabled: Bool
    let perform: () -> Void
}
struct CurveContextSurface: NSViewRepresentable {
    let action: (CGPoint) -> CurveContextAction
    func makeNSView(context: Context) -> Surface { let view = Surface(); view.action = action; view.enabled = context.environment.isEnabled; return view }
    func updateNSView(_ view: Surface, context: Context) { view.action = action; view.enabled = context.environment.isEnabled }
    @MainActor final class Surface: NSView {
        var enabled = true
        var action: (CGPoint) -> CurveContextAction = { _ in .init(enabled: false, perform: {}) }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard enabled, bounds.contains(point), NSApp.currentEvent?.type == .rightMouseDown else { return nil }; return self
        }
        override func rightMouseDown(with event: NSEvent) {
            apply(at: convert(event.locationInWindow, from: nil))
        }
        func apply(at point: CGPoint) {
            guard enabled else { return }
            let selected = action(point)
            if selected.enabled { selected.perform() }
        }
    }
}
