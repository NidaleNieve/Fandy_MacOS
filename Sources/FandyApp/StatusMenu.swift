import SwiftUI
import AppKit
import FandyCore

/// AppKit provides actual hierarchical menus with embedded controls; the editor remains SwiftUI.
@MainActor final class StatusMenu: NSObject, NSMenuDelegate {
    let model: AppModel
    let item: NSStatusItem?
    var openProfiles: () -> Void = {}
    var openSettings: () -> Void = {}
    private var observation: Task<Void, Never>?
    private var actions: [UUID: () -> Void] = [:]
    private var pickerPopover: NSPopover?
    private var profileRows: [String: NSMenuItem] = [:]
    private var timingRow: NSMenuItem?
    init(model: AppModel, install: Bool = true) {
        self.model = model; item = install ? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) : nil; super.init()
        let menu = NSMenu(); menu.delegate = self; item?.menu = menu
        item?.button?.image = NSImage(systemSymbolName: "fan", accessibilityDescription: "Fandy")
        item?.button?.imagePosition = .imageLeading
        updateTitle()
        guard install else { return }
        observation = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { break }
                self?.updateTitle()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }
    func show() { item?.button?.performClick(nil) }
    private func refreshSelection() {
        for (id, row) in profileRows { row.state = model.menuSelectionID == id ? .on : .off }
        timingRow?.isEnabled = model.canSetActivationLimit
    }
    func updateTitle() {
        refreshSelection()
        let text = ([model.automation.preferences.showClock ? model.formattedTime(Date()) : nil, model.sensorMenu.compactText.isEmpty ? nil : model.sensorMenu.compactText].compactMap { $0 }).joined(separator: "  ")
        item?.button?.title = text.isEmpty ? "" : " " + text
        item?.button?.toolTip = model.statusText + " · " + model.activationDescription
    }
    func menuWillOpen(_ menu: NSMenu) { rebuild(menu) }
    func rebuild(_ menu: NSMenu) {
        actions.removeAll(); profileRows.removeAll(); menu.removeAllItems(); menu.autoenablesItems = false
        for profile in model.profiles {
            let row = add(profile.name, to: menu) { [weak model] in model?.select(profile.id) }
            row.view = fitted(ProfileMenuRow(model: model, profile: profile, select: { [weak self] in self?.model.select(profile.id); self?.refreshSelection() }))
            profileRows[profile.id] = row; row.state = model.menuSelectionID == profile.id ? .on : .off
            row.toolTip = model.eligibility(profile).reason
        }
        menu.addItem(.separator())
        let timing = submenu("Activate for/until", in: menu)
        timingRow = menu.items.last; timingRow?.isEnabled = model.canSetActivationLimit
        let minutes = submenu("Minutes", in: timing)
        for value in stride(from: 5, through: 55, by: 5) {
            add("\(value) minutes", to: minutes) { [weak model] in model?.activateFor(seconds: Double(value * 60)) }
            if [5,15,25,35,45].contains(value) { minutes.addItem(.separator()) }
        }
        let hours = submenu("Hours", in: timing)
        for value in Array(1...12) + [24] {
            if value == 24 { hours.addItem(.separator()) }
            add("\(value) \(value == 1 ? "hour" : "hours")", to: hours) { [weak model] in model?.activateFor(seconds: Double(value * 3600)) }
        }
        let custom = submenu("Other Time/Until", in: timing)
        add("Choose Duration or Time…", to: custom) { [weak self] in self?.presentPicker(time: true) }
        let apps = submenu("While App Is Running", in: timing)
        add("Choose Running Application…", to: apps) { [weak self] in self?.presentPicker(time: false) }
        timing.addItem(.separator())
        let forever = add("Until changed", to: timing) { [weak model] in model?.activateForever() }
        if case .forever = model.manualIntent?.limit { forever.state = .on }
        let explanation = NSMenuItem(); explanation.view = fitted(ActivationMenuSummary(model: model)); if let view = explanation.view { view.frame.size.height = max(64, view.fittingSize.height) }; menu.addItem(explanation)
        let cancel = add(model.cancellationTitle, to: menu) { [weak model] in model?.cancelActivation() }
        cancel.view = fitted(CancellationMenuRow(model: model)); if let view = cancel.view { view.frame.size.height = max(36, view.fittingSize.height) }
        menu.addItem(.separator())
        let status = NSMenuItem(); status.view = fitted(FanMenuStatus(model: model)); if let view = status.view { view.frame.size.height = max(80, view.fittingSize.height) }; menu.addItem(status)
        menu.addItem(.separator())
        add("Edit Profiles…", to: menu) { [weak self] in self?.openProfiles() }
        add("Settings…", to: menu) { [weak self] in self?.openSettings() }
        let quit = add("Quit", to: menu) { [weak model] in model?.quit() }; quit.keyEquivalent = "q"
    }
    @discardableResult private func add(_ title: String, to menu: NSMenu, action: @escaping () -> Void) -> NSMenuItem {
        let id = UUID(); actions[id] = action
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = id
        item.view = fitted(Button(action: action) { WrappedMenuText(text: title) }.buttonStyle(MenuActionStyle()))
        menu.addItem(item); return item
    }
    @objc private func invoke(_ item: NSMenuItem) { if let id = item.representedObject as? UUID { actions[id]?() } }
    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let child = NSMenu(title: title); child.autoenablesItems = false
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = child; menu.addItem(item); return child
    }
    private func presentPicker(time: Bool) {
        guard let button = item?.button else { return }
        item?.menu?.cancelTracking()
        // Apple's NSMenu custom views do not support keyboard input. Use an
        // anchored native popover for searchable apps and editable time fields.
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self, let button else { return }
            self.pickerPopover?.close()
            let popover = NSPopover(); popover.behavior = .transient; popover.animates = false
            if time { popover.contentViewController = NSHostingController(rootView: CustomActivationPicker(model: self.model, close: { [weak popover] in popover?.close() })) }
            else { popover.contentViewController = NSHostingController(rootView: ProcessPicker(model: self.model, close: { [weak popover] in popover?.close() })) }
            self.pickerPopover = popover; NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    private func fitted<V: View>(_ view: V) -> NSView {
        let hosting = NSHostingView(rootView: view); hosting.frame.size = NSSize(width: MenuLayout.width, height: max(28, hosting.fittingSize.height)); return hosting
    }
    private func host<V: View>(_ view: V, size: NSSize) -> NSMenuItem {
        let item = NSMenuItem(); let hosting = NSHostingView(rootView: view); hosting.frame.size = size; item.view = hosting; return item
    }
}

struct CancellationMenuRow: View {
    @Bindable var model: AppModel
    var body: some View { Button { model.cancelActivation() } label: { WrappedMenuText(text: model.cancellationTitle) }.buttonStyle(MenuActionStyle()) }
}
struct ActivationMenuSummary: View {
    @Bindable var model: AppModel
    var body: some View { WrappedMenuText(text: model.activationDescription).foregroundStyle(.secondary) }
}
struct CustomActivationPicker: View {
    @Bindable var model: AppModel
    let close: () -> Void
    @State private var until = false
    @State private var hours = "1"
    @State private var minutes = "0"
    @State private var untilHours = String(Calendar.current.component(.hour, from: Date()))
    @State private var untilMinutes = String(format: "%02d", Calendar.current.component(.minute, from: Date()))
    @State private var afternoon = Calendar.current.component(.hour, from: Date()) >= 12
    @State private var error: String?
    enum Field: Hashable { case hours, minutes }
    @FocusState private var focused: Field?
    @State private var editing: Field = .hours
    private var clockHour: Int {
        let h = Int(untilHours) ?? 0
        return model.automation.preferences.use24HourTime ? h : h % 12 + (afternoon ? 12 : 0)
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                segment("For", value: false); segment("Until", value: true)
            }.background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 6))
            if until {
                HStack {
                    timeField("Hours", text: $untilHours, field: .hours)
                    Text(":")
                    timeField("Minutes", text: $untilMinutes, field: .minutes)
                    if !model.automation.preferences.use24HourTime {
                        Picker("Period", selection: $afternoon) { Text("AM").tag(false); Text("PM").tag(true) }.labelsHidden().frame(width: 75)
                    }
                }
                TimeDial(hour: Binding(get: { clockHour }, set: { value in afternoon = value >= 12; untilHours = String(model.automation.preferences.use24HourTime ? value : (value % 12 == 0 ? 12 : value % 12)) }), minute: Binding(get: { Int(untilMinutes) ?? 0 }, set: { untilMinutes = String(format: "%02d", $0) }), editingMinutes: editing == .minutes, use24HourTime: model.automation.preferences.use24HourTime)
            } else {
                HStack { timeField("Hours", text: $hours, field: .hours); Text("hours") }
                HStack { timeField("Minutes", text: $minutes, field: .minutes); Text("minutes") }
                Spacer(minLength: 0)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Button("Continue") { apply() }.buttonStyle(.borderedProminent).tint(.accentColor)
        }.padding(16).frame(width: MenuLayout.width, height: 350)
        .onChange(of: focused) { _, value in if let value { editing = value } }
        .onChange(of: until) { _, _ in
            focused = .hours; error = nil
            if !model.automation.preferences.use24HourTime { let h = clockHour % 12; untilHours = String(h == 0 ? 12 : h) }
        }
    }
    private func segment(_ title: String, value: Bool) -> some View {
        Button { until = value } label: { Text(title).frame(maxWidth: .infinity).padding(.vertical, 5).background(until == value ? Color.accentColor : .clear).foregroundStyle(until == value ? .white : .primary) }.buttonStyle(.borderless)
    }
    private func timeField(_ label: String, text: Binding<String>, field: Field) -> some View {
        TextField(label, text: text).textFieldStyle(.roundedBorder).frame(width: 58).focused($focused, equals: field)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(focused == field ? Color.accentColor : .clear, lineWidth: 2))
            .onTapGesture { editing = field; focused = field }.accessibilityLabel(label)
    }
    private func apply() {
        func integer(_ text: String) -> Int? { guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }; return Int(text) }
        if until {
            guard let h = integer(untilHours), let m = integer(untilMinutes), (0...59).contains(m), (model.automation.preferences.use24HourTime ? 0...23 : 1...12).contains(h),
                  let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: clockHour, minute: m), matchingPolicy: .nextTime, repeatedTimePolicy: .first) else { error = "Enter a valid hour and minute."; return }
            model.activateUntil(next)
        } else {
            guard let h = integer(hours), let m = integer(minutes), (0...743).contains(h), (0...59).contains(m), h + m > 0 else { error = "Enter a positive duration."; return }
            model.activateFor(seconds: Double(h*3600+m*60))
        }
        error = nil; close()
    }
}
struct ProcessPicker: View {
    @Bindable var model: AppModel
    let close: () -> Void
    @State private var search = ""
    private var helpers: Bool { model.automation.preferences.showHelperProcesses }
    @State private var processes: [RunningProcess] = []
    private var filtered: [RunningProcess] { processes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search running apps", text: $search).textFieldStyle(.roundedBorder)
            Toggle("Show helper apps and processes", isOn: Binding(get: { helpers }, set: { enabled in model.setPreferences { $0.showHelperProcesses = enabled } }))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { process in
                        Button {
                            model.activateWhile(process); close()
                        } label: {
                            HStack {
                                if let icon = process.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                                else { Image(systemName: "app").frame(width: 20) }
                                Text(process.name).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if helpers { Text(String(process.pid)).font(.caption).foregroundStyle(.secondary) }
                            }.padding(4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button("Refresh") { refresh() }.font(.caption)
        }.padding(12).frame(width: 330, height: 350)
        .onAppear { refresh() }.onChange(of: helpers) { _, _ in refresh() }
    }
    private func refresh() { processes = ProcessCatalog.list(includeHelpers: helpers) }
}
