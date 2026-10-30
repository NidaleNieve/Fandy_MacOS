import AppKit
import SwiftUI
import Foundation

struct ProcessMemorySample: Codable {
    let footprintBytes: UInt64
    static func current() throws -> Self {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw CocoaError(.executableRuntimeMismatch) }
        return Self(footprintBytes: info.phys_footprint)
    }
}

/// Exercises native view lifecycles offscreen. No hardware reader, fan command,
/// user configuration changes, screenshots, clicks or synthetic heat workloads.
@MainActor enum BackgroundMemoryDiagnostics {
    static func run() async -> Int32 {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FandyMemory-\(UUID().uuidString)")
        let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
        defer { model.stop(); try? FileManager.default.removeItem(at: dir) }
        do {
            try await Task.sleep(for: .seconds(3))
            let cold = try ProcessMemorySample.current()
            let menu = NSMenu(), presenter = StatusMenu(model: model, install: false)
            for _ in 0..<3 {
                autoreleasepool { presenter.menuWillOpen(menu); presenter.menuDidClose(menu) }
                try await Task.sleep(for: .seconds(1))
            }
            try await Task.sleep(for: .seconds(3))
            let menuOnly = try ProcessMemorySample.current()
            for _ in 0..<3 {
                autoreleasepool {
                    let window = ProfilesWindow.make(content: EmptyView())
                    window.contentViewController = nil
                    let content = WindowContentLifecycle(window: window) { ProfileHostingController(rootView: ProfileEditor(model: model)) }
                    content.prepare(); window.contentView?.layoutSubtreeIfNeeded(); window.close()
                    let settings = ProfilesWindow.make(content: EmptyView()); settings.contentViewController = nil
                    let settingsContent = WindowContentLifecycle(window: settings) { ProfileHostingController(rootView: SettingsView(model: model)) }
                    settingsContent.prepare(); settings.contentView?.layoutSubtreeIfNeeded(); settings.close()
                    presenter.menuWillOpen(menu); presenter.menuDidClose(menu)
                }
                try await Task.sleep(for: .seconds(1))
            }
            try await Task.sleep(for: .seconds(10))
            let settled = try ProcessMemorySample.current()
            var data = try JSONEncoder().encode(["cold": cold, "afterThreeClosedMenuCycles": menuOnly, "afterThreeClosedUICycles": settled])
            data.append(10); FileHandle.standardOutput.write(data)
            return menu.numberOfItems == 0 ? 0 : 1
        } catch { return 1 }
    }
}
