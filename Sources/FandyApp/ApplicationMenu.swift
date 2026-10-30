import AppKit

/// Standard responder-chain commands formerly supplied by SwiftUI's App scene.
@MainActor enum ApplicationMenu {
    static func make(target: AppDelegate) -> NSMenu {
        let root = NSMenu()
        let application = NSMenu(title: "Fandy")
        let appItem = NSMenuItem(); appItem.submenu = application; root.addItem(appItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettingsWindow(_:)), keyEquivalent: ",")
        settings.target = target; application.addItem(settings); application.addItem(.separator())
        application.addItem(withTitle: "Hide Fandy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(withTitle: "Quit Fandy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit"), editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit; root.addItem(editItem)
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        return root
    }
}
