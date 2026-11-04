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
        let left = NSSplitViewItem(viewController: ProfileHostingController(rootView: sidebar))
        left.canCollapse = false; left.minimumThickness = 220; left.maximumThickness = 350; left.holdingPriority = .defaultHigh
        let right = NSSplitViewItem(viewController: ProfileHostingController(rootView: detail))
        right.canCollapse = false; right.minimumThickness = 660
        controller.addSplitViewItem(left); controller.addSplitViewItem(right)
        controller.splitView.setPosition(240, ofDividerAt: 0)
        return controller
    }
    // Retain both roots across sensor ticks to preserve layout and interaction state.
    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {}
}

/// Let the window and split view size hosted content; intrinsic widths can overflow columns.
@MainActor protocol ReleasableHostingContent { func discardContent() }

@MainActor final class ProfileHostingController<Content: View>: NSHostingController<Content?>, ReleasableHostingContent {
    init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        if let hosting = view as? NSHostingView<Content?> { hosting.sizingOptions = [] }
    }
    func discardContent() { rootView = nil; view.layoutSubtreeIfNeeded() }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad()
        sizingOptions = []
        if let hosting = view as? NSHostingView<Content?> { hosting.sizingOptions = [] }
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        Self.hideScrollIndicators(in: view)
    }
    static func hideScrollIndicators(in view: NSView) {
        if let scroll = view as? NSScrollView {
            if scroll.hasVerticalScroller { scroll.hasVerticalScroller = false }
            if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
        }
        for child in view.subviews { hideScrollIndicators(in: child) }
    }
}
