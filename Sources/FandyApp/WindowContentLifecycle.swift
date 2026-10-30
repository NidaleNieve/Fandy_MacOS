import AppKit
import Observation
import FandyCore

/// Keep native geometry, not an offscreen SwiftUI graph, between window visits.
@MainActor final class WindowContentLifecycle: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let makeContent: () -> NSViewController
    private let minimumContentSize: NSSize
    private var splitPositions: [CGFloat] = []
    init(window: NSWindow, makeContent: @escaping () -> NSViewController) {
        self.window = window; self.makeContent = makeContent; self.minimumContentSize = window.contentMinSize
        super.init(); window.delegate = self
    }
    func prepare() {
        guard window.contentViewController == nil else { return }
        let frame = window.frame
        window.contentViewController = makeContent()
        window.contentMinSize = minimumContentSize
        window.setFrame(frame, display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        for (split, position) in zip(splits(in: window.contentView), splitPositions) {
            split.setPosition(position, ofDividerAt: 0)
        }
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimum = NSWindow.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize), styleMask: sender.styleMask).size
        return NSSize(width: max(frameSize.width, minimum.width), height: max(frameSize.height, minimum.height))
    }
    func windowWillClose(_ notification: Notification) {
        let frame = window.frame
        autoreleasepool {
            splitPositions = splits(in: window.contentView).compactMap { $0.subviews.first?.frame.width }
            (window.contentViewController as? any ReleasableHostingContent)?.discardContent()
            window.contentViewController = nil
            window.contentView = nil
            window.toolbar = nil
        }
        window.setFrame(frame, display: false)
        BackgroundMemoryReclaimer.shared.schedule()
    }
    private func splits(in view: NSView?) -> [NSSplitView] {
        guard let view else { return [] }
        return (view as? NSSplitView).map { [$0] } ?? view.subviews.flatMap { splits(in: $0) }
    }
}

/// Small editor values survive closing without retaining views, graphs or images.
@MainActor @Observable final class EditorPresentationState {
    enum Tab: String, CaseIterable { case curves = "Fan Curves", schedule = "Schedule", pauses = "Pause Schedule", activation = "When Activated" }
    var tab = Tab.curves
    var chipExpanded = true
    var chassisExpanded = true
    @ObservationIgnored private var drafts: [String: (base: FanCurve, draft: CurveDraft)] = [:]
    func saveDraft(_ draft: CurveDraft, for key: String, base: FanCurve) { drafts[key] = (base, draft) }
    func draft(for key: String, curve: FanCurve) -> CurveDraft {
        guard let saved = drafts[key], saved.base == curve else { drafts[key] = nil; return CurveDraft(curve) }
        return saved.draft
    }
}
