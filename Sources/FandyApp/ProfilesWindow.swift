import AppKit
import SwiftUI

/// AppKit owns the window size. Hosting changes cannot collapse it to the
/// split view's transient fitting height during initial layout or tab changes.
@MainActor final class ProfilesWindow: NSWindow {
    static let initialContentSize = NSSize(width: 1040, height: 720)
    static let minimumContentSize = NSSize(width: 780, height: 480)

    static func make<Content: View>(content: Content) -> ProfilesWindow {
        let window = ProfilesWindow(contentRect: NSRect(origin: .zero, size: initialContentSize),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Fandy Profiles"; window.isReleasedWhenClosed = false
        window.contentViewController = ProfileHostingController(rootView: content)
        window.contentMinSize = minimumContentSize
        // Attaching a hosting controller can change the frame. Apply the intended
        // launch size after attachment, not just to the initializer's content rect.
        window.setContentSize(initialContentSize); window.center()
        return window
    }
    private func bounded(_ proposed: NSRect) -> NSRect {
        let minimum = frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        var frame = proposed
        frame.size.width = max(proposed.width, minimum.width)
        frame.size.height = max(proposed.height, minimum.height)
        frame.origin.y -= frame.height - proposed.height
        return frame
    }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) { super.setFrame(bounded(frameRect), display: flag) }
    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) { super.setFrame(bounded(frameRect), display: flag, animate: animate) }
    override func setContentSize(_ size: NSSize) {
        super.setContentSize(NSSize(width: max(size.width, Self.minimumContentSize.width), height: max(size.height, Self.minimumContentSize.height)))
    }
}
