import AppKit
import SwiftUI

/// A native search control, independent of Form's trailing value alignment.
struct NativeSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(); field.placeholderString = placeholder
        field.alignment = .left; field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.stringValue = text
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { text.wrappedValue = field.stringValue }
        }
    }
}
