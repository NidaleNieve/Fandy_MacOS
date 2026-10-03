import AppKit
import SwiftUI
import Carbon
import FandyCore

struct ShortcutIDSequence {
    var value: UInt32 = 0
    mutating func next() -> UInt32? { guard value < UInt32.max else { return nil }; value += 1; return value }
}

/// Registers only explicit shortcuts; no event tap, global key monitor, or Accessibility permission.
@MainActor final class GlobalShortcuts {
    private static weak var active: GlobalShortcuts?
    static var recording = false { didSet { if recording != oldValue { active?.pauseRecording(recording) } } }
    private var paused = false
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var actions: [UInt32: String] = [:]
    private var bindings: [String: ShortcutBinding] = [:]
    private var sequence = ShortcutIDSequence()
    var invoke: (String) -> Void = { _ in }
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            guard id.signature == 0x46616e64 else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { if !GlobalShortcuts.recording, let action = service.actions[id.id] { service.invoke(action) } }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        Self.active = self
    }
    func update(_ next: [String: ShortcutBinding]) -> [String: String] {
        guard !paused else { bindings = next; return errors }
        guard next != bindings else { return errors }
        for ref in registrations { UnregisterEventHotKey(ref) }
        registrations = []; actions = [:]; bindings = next; errors = [:]
        guard handler != nil else { errors = Dictionary(uniqueKeysWithValues: next.keys.map { ($0, "Shortcut registration unavailable.") }); return errors }
        for action in next.keys.sorted() {
            guard let binding = next[action], (try? binding.validate()) != nil else { continue }
            var modifiers: UInt32 = 0
            if binding.modifiers & 1 != 0 { modifiers |= UInt32(cmdKey) }
            if binding.modifiers & 2 != 0 { modifiers |= UInt32(optionKey) }
            if binding.modifiers & 4 != 0 { modifiers |= UInt32(controlKey) }
            if binding.modifiers & 8 != 0 { modifiers |= UInt32(shiftKey) }
            guard let id = sequence.next() else { errors[action] = "Restart Fandy to register more shortcuts."; continue }
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(binding.keyCode, modifiers, EventHotKeyID(signature: 0x46616e64, id: id), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { registrations.append(ref); actions[id] = action }
            else { errors[action] = "Unavailable: this shortcut may already be used by macOS or another app." }
        }
        return errors
    }
    private func pauseRecording(_ value: Bool) {
        paused = value
        if value {
            for ref in registrations { UnregisterEventHotKey(ref) }; registrations = []; actions = [:]
        } else { let saved = bindings; bindings = [:]; _ = update(saved) }
    }
    private var errors: [String: String] = [:]
    func stop() {
        if Self.active === self { Self.active = nil; Self.recording = false }
        for ref in registrations { UnregisterEventHotKey(ref) }; registrations = []
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
}

struct ShortcutSettings: View {
    @Bindable var model: AppModel
    var body: some View {
        Section("Keyboard Shortcuts") {
            shortcut("Toggle Menu", id: "menu")
            ForEach(model.profiles) { profile in shortcut(profile.name, id: profile.id) }
        }
    }
    private func shortcut(_ title: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title); Spacer()
                ShortcutRecorder(binding: model.automation.preferences.shortcuts[id]) { binding in
                    model.setPreferences { prefs in prefs.shortcuts[id] = binding }
                }.frame(width: 140, height: 26)
                Button { model.setPreferences { $0.shortcuts.removeValue(forKey: id) } } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).disabled(model.automation.preferences.shortcuts[id] == nil).help("Clear shortcut")
            }
            if let error = model.shortcutErrors[id] { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}
struct ShortcutRecorder: NSViewRepresentable {
    let binding: ShortcutBinding?
    let change: (ShortcutBinding) -> Void
    func makeNSView(context: Context) -> RecorderButton { let button = RecorderButton(); button.change = change; button.shortcut = binding; return button }
    func updateNSView(_ view: RecorderButton, context: Context) { view.change = change; view.shortcut = binding; view.refresh() }
    @MainActor final class RecorderButton: NSButton {
        var change: (ShortcutBinding) -> Void = { _ in }
        var shortcut: ShortcutBinding?
        var recording = false
        override var acceptsFirstResponder: Bool { true }
        init() { super.init(frame: .zero); bezelStyle = .rounded; target = self; action = #selector(record); refresh() }
        required init?(coder: NSCoder) { fatalError("Not used") }
        func refresh() { title = recording ? "Press shortcut…" : shortcut?.label ?? "Record…" }
        @objc private func record() { recording = true; GlobalShortcuts.recording = true; window?.makeFirstResponder(self); refresh() }
        override func resignFirstResponder() -> Bool { recording = false; GlobalShortcuts.recording = false; refresh(); return true }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { if recording { keyDown(with: event); return true }; return false }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { recording = false; GlobalShortcuts.recording = false; refresh(); return }
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= 1 }
            if event.modifierFlags.contains(.option) { modifiers |= 2 }
            if event.modifierFlags.contains(.control) { modifiers |= 4 }
            if event.modifierFlags.contains(.shift) { modifiers |= 8 }
            let symbols: [UInt16: String] = [123:"←",124:"→",125:"↓",126:"↑",36:"↩",48:"⇥",49:"Space",51:"⌫",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"]
            let key = symbols[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
            let binding = ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
            guard (try? binding.validate()) != nil else { title = "Add a modifier…"; return }
            recording = false; GlobalShortcuts.recording = false; change(binding); refresh()
        }
    }
}
