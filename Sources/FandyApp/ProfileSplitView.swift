import SwiftUI
import AppKit

/// An adjustable sidebar that never collapses and has no collapse toolbar item.
struct ProfileSplitView<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    let sidebar: Sidebar
    let detail: Detail
    init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) { self.sidebar = sidebar(); self.detail = detail() }
    func makeNSViewController(context: Context) -> NSSplitViewController { makeController() }
    func makeController() -> NSSplitViewController {
        let controller = NSSplitViewController(); controller.splitView.isVertical = true
        let left = NSSplitViewItem(viewController: NSHostingController(rootView: sidebar))
        left.canCollapse = false; left.minimumThickness = 220; left.maximumThickness = 350; left.holdingPriority = .defaultHigh
        let right = NSSplitViewItem(viewController: NSHostingController(rootView: detail))
        right.canCollapse = false; right.minimumThickness = 660
        controller.addSplitViewItem(left); controller.addSplitViewItem(right)
        controller.splitView.setPosition(240, ofDividerAt: 0)
        return controller
    }
    // Both roots retain the same observable model. Replacing them on each sensor
    // tick discards native sizing/interaction state and invalidates the editor.
    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {}
}
