import SwiftUI
import AppKit

/// AppKit's traditional analog clock, kept in the menu's own hosting view.
struct TimeDial: NSViewRepresentable {
    @Binding var hour: Int
    @Binding var minute: Int
    let use24HourTime: Bool
    func makeCoordinator() -> Coordinator { Coordinator(hour: $hour, minute: $minute) }
    func makeNSView(context: Context) -> NSDatePicker {
        let picker = Self.makePicker()
        picker.target = context.coordinator; picker.action = #selector(Coordinator.changed(_:))
        updateNSView(picker, context: context)
        return picker
    }
    static func makePicker() -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar; picker.datePickerElements = [.hourMinute]
        picker.datePickerMode = .single; picker.isBordered = false
        picker.appearance = NSAppearance(named: .aqua)
        picker.setAccessibilityLabel("Until time")
        picker.sizeToFit()
        return picker
    }
    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.hour = $hour; context.coordinator.minute = $minute
        picker.locale = Locale(identifier: use24HourTime ? "en_GB" : "en_US")
        picker.timeZone = .current
        let calendar = Calendar.current
        guard (0...23).contains(hour), (0...59).contains(minute),
              let value = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: picker.dateValue) else { return }
        if calendar.component(.hour, from: picker.dateValue) != hour || calendar.component(.minute, from: picker.dateValue) != minute {
            picker.dateValue = value
        }
    }
    @MainActor final class Coordinator: NSObject {
        var hour: Binding<Int>
        var minute: Binding<Int>
        init(hour: Binding<Int>, minute: Binding<Int>) { self.hour = hour; self.minute = minute }
        @objc func changed(_ picker: NSDatePicker) {
            hour.wrappedValue = Calendar.current.component(.hour, from: picker.dateValue)
            minute.wrappedValue = Calendar.current.component(.minute, from: picker.dateValue)
        }
    }
}
