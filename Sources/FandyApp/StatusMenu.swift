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
    func updateTitle() {
        let text = ([model.automation.preferences.showClock ? model.formattedTime(Date()) : nil, model.sensorMenu.compactText.isEmpty ? nil : model.sensorMenu.compactText].compactMap { $0 }).joined(separator: "  ")
        item?.button?.title = text.isEmpty ? "" : " " + text
        item?.button?.toolTip = model.statusText + " · " + model.activationDescription
    }
    func menuWillOpen(_ menu: NSMenu) { rebuild(menu) }
    func rebuild(_ menu: NSMenu) {
        actions.removeAll(); menu.removeAllItems(); menu.autoenablesItems = false
        for profile in model.profiles {
            let row = add(profile.name, to: menu) { [weak model] in model?.select(profile.id) }
            row.state = model.isSelected(profile.id) ? .on : .off
            row.isEnabled = model.canActivate(profile)
            row.toolTip = model.eligibility(profile).reason
        }
        menu.addItem(.separator())
        let timing = submenu("Activate for/until", in: menu)
        menu.items.last?.isEnabled = model.isSelected(model.machine.selected.id)
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
        custom.addItem(host(CustomActivationPicker(model: model, close: { [weak menu] in menu?.cancelTracking() }), size: NSSize(width: 280, height: 255)))
        let apps = submenu("While App Is Running", in: timing)
        apps.addItem(host(ProcessPicker(model: model, close: { [weak menu] in menu?.cancelTracking() }), size: NSSize(width: 330, height: 350)))
        timing.addItem(.separator())
        let forever = add("Until changed", to: timing) { [weak model] in model?.activateForever() }
        if case .forever = model.manualIntent?.limit { forever.state = .on }
        let explanation = NSMenuItem(title: model.activationDescription, action: nil, keyEquivalent: ""); explanation.isEnabled = false; menu.addItem(explanation)
        add(model.manualIntent == nil ? "Resume Schedule" : "Cancel Override / Resume Schedule", to: menu) { [weak model] in model?.resumeSchedule() }
        menu.addItem(.separator())
        let status = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: ""); status.isEnabled = false; menu.addItem(status)
        menu.addItem(.separator())
        add("Edit Profiles…", to: menu) { [weak self] in self?.openProfiles() }
        add("Settings…", to: menu) { [weak self] in self?.openSettings() }
        let quit = add("Quit", to: menu) { [weak model] in model?.quit() }; quit.keyEquivalent = "q"
    }
    @discardableResult private func add(_ title: String, to menu: NSMenu, action: @escaping () -> Void) -> NSMenuItem {
        let id = UUID(); actions[id] = action
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = id; menu.addItem(item); return item
    }
    @objc private func invoke(_ item: NSMenuItem) { if let id = item.representedObject as? UUID { actions[id]?() } }
    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let child = NSMenu(title: title); child.autoenablesItems = false
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = child; menu.addItem(item); return child
    }
    private func host<V: View>(_ view: V, size: NSSize) -> NSMenuItem {
        let item = NSMenuItem(); let hosting = NSHostingView(rootView: view); hosting.frame.size = size; item.view = hosting; return item
    }
}

struct CustomActivationPicker: View {
    @Bindable var model: AppModel
    let close: () -> Void
    @State private var until = false
    @State private var hours = "1"
    @State private var minutes = "0"
    @State private var time = Date()
    @State private var error: String?
    var body: some View {
        VStack(spacing: 16) {
            Picker("Activation", selection: $until) { Text("For").tag(false); Text("Until").tag(true) }.pickerStyle(.segmented)
            if until {
                DatePicker("Time", selection: $time, displayedComponents: [.hourAndMinute])
                    .environment(\.locale, Locale(identifier: model.automation.preferences.use24HourTime ? "en_GB" : "en_US"))
                Text("Next occurrence of this time").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack { Stepper("Hours", value: Binding(get: { Int(hours) ?? 0 }, set: { hours = String($0) }), in: 0...743); TextField("Hours", text: $hours).frame(width: 48) }
                HStack { Stepper("Minutes", value: Binding(get: { Int(minutes) ?? 0 }, set: { minutes = String($0) }), in: 0...59); TextField("Minutes", text: $minutes).frame(width: 48) }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Button("Continue") {
                if until {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                    guard let next = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first) else { error = "Time unavailable"; return }
                    model.activateUntil(next)
                } else {
                    guard hours.utf8.allSatisfy({ (48...57).contains($0) }), minutes.utf8.allSatisfy({ (48...57).contains($0) }), let hours = Int(hours), let minutes = Int(minutes), (0...743).contains(hours), (0...59).contains(minutes), hours + minutes > 0 else { error = "Enter a positive duration."; return }
                    model.activateFor(seconds: Double(hours * 3600 + minutes * 60))
                }
                close()
            }.buttonStyle(.borderedProminent)
        }.padding(16).frame(width: 280, height: 255)
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
                                Text(process.name).lineLimit(1)
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
