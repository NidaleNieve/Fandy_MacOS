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
        left.canCollapse = false; left.minimumThickness = 170; left.maximumThickness = 350; left.holdingPriority = .defaultHigh
        let right = NSSplitViewItem(viewController: ProfileHostingController(rootView: detail))
        right.canCollapse = false; right.minimumThickness = 590
        controller.addSplitViewItem(left); controller.addSplitViewItem(right)
        controller.splitView.setPosition(210, ofDividerAt: 0)
        return controller
    }
    // Both roots retain the same observable model. Replacing them on each sensor
    // tick discards native sizing/interaction state and invalidates the editor.
    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {}
}

/// The window and split view own layout, not the changing ideal width of a
/// segmented picker, grid or graph. Intrinsic hosting constraints otherwise
/// temporarily push the columns outside the window during SwiftUI updates.
@MainActor final class ProfileHostingController<Content: View>: NSHostingController<Content> {
    override init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        if let hosting = view as? NSHostingView<Content> { hosting.sizingOptions = [] }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad()
        sizingOptions = []
        if let hosting = view as? NSHostingView<Content> { hosting.sizingOptions = [] }
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

/// The monitoring column has its own native divider and stays visible.
struct ProfileDetailSplitView<Editor: View, Monitoring: View>: NSViewControllerRepresentable {
    let editor: Editor
    let monitoring: Monitoring
    init(@ViewBuilder editor: () -> Editor, @ViewBuilder monitoring: () -> Monitoring) { self.editor = editor(); self.monitoring = monitoring() }
    func makeNSViewController(context: Context) -> NSSplitViewController { makeController() }
    func makeController() -> NSSplitViewController {
        let controller = NSSplitViewController(); controller.splitView.isVertical = true
        let main = NSSplitViewItem(viewController: ProfileHostingController(rootView: editor))
        main.canCollapse = false; main.minimumThickness = 400; main.holdingPriority = .defaultLow
        let status = NSSplitViewItem(viewController: ProfileHostingController(rootView: monitoring))
        status.canCollapse = false; status.minimumThickness = 170; status.maximumThickness = 300; status.holdingPriority = .defaultHigh
        controller.addSplitViewItem(main); controller.addSplitViewItem(status)
        controller.splitView.setPosition(605, ofDividerAt: 0)
        return controller
    }
    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {}
}
