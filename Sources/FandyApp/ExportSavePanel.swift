import AppKit
import UniformTypeIdentifiers

@MainActor enum ExportSavePanel {
    static func make(filename: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = filename
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return panel
    }
}
