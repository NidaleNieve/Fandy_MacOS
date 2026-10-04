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
    private var profileRows: [String: NSMenuItem] = [:]
    private var timingRow: NSMenuItem?
    private(set) var isOpen = false
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
    func toggle() {
        if isOpen { item?.menu?.cancelTracking() }
        else { item?.button?.performClick(nil) }
    }
    private func refreshSelection() {
        for (id, row) in profileRows { row.state = model.menuSelectionID == id ? .on : .off; row.view?.needsDisplay = true }
        timingRow?.isEnabled = model.canSetActivationLimit
    }
    func updateTitle() {
        refreshSelection()
        let text = model.sensorMenu.compactText
        item?.button?.title = text.isEmpty ? "" : " " + text
        item?.button?.toolTip = model.statusText + " · " + model.activationDescription
    }
    func menuWillOpen(_ menu: NSMenu) { isOpen = true; rebuild(menu) }
    func menuDidClose(_ menu: NSMenu) { isOpen = false }
    func rebuild(_ menu: NSMenu) {
        actions.removeAll(); profileRows.removeAll(); menu.removeAllItems(); menu.autoenablesItems = false; menu.minimumWidth = MenuLayout.width
        for profile in model.profiles {
            let row = add(profile.name, to: menu) { [weak model] in model?.select(profile.id) }
            if profile.kind != .system && model.needsHelperSetup { row.image = AppModel.approvalDot() }
            row.isEnabled = model.canActivate(profile) && model.activationDefaultUnavailableReason(profile) == nil
            profileRows[profile.id] = row; row.state = model.menuSelectionID == profile.id ? .on : .off
            row.toolTip = profile.kind != .system && model.needsHelperSetup ? model.helperSetupMessage : model.activationDefaultUnavailableReason(profile) ?? model.eligibility(profile).reason ?? profile.name
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
        let time = submenu("Other Time/Until", in: timing)
        let timeControls = NSMenuItem()
        timeControls.view = embedded(CustomActivationPicker(model: model, close: { [weak menu] in menu?.cancelTracking() }), identifier: "activation.time")
        time.addItem(timeControls)
        let applications = submenu("While App Is Running", in: timing)
        let appControls = NSMenuItem()
        appControls.view = embedded(ProcessPicker(model: model, close: { [weak menu] in menu?.cancelTracking() }), identifier: "activation.application")
        applications.addItem(appControls)
        timing.addItem(.separator())
        let forever = add("Until Changed", to: timing) { [weak model] in model?.activateForever() }
        if case .forever = model.manualIntent?.limit { forever.state = .on }
        if (model.manualIntent.map { $0.limit != .forever } ?? false) || model.scheduledPeriodID != nil {
            let explanation = NSMenuItem(); explanation.view = fitted(ActivationMenuSummary(model: model)); menu.addItem(explanation)
        }
        if model.showsCancellation {
            add(model.cancellationTitle, to: menu) { [weak model] in model?.cancelActivation() }
        }
        menu.addItem(.separator())
        let status = NSMenuItem(); status.view = fitted(FanMenuStatus(model: model)); menu.addItem(status)
        menu.addItem(.separator())
        if model.needsHelperSetup {
            let notice = NSMenuItem()
            notice.view = fitted(HelperApprovalNotice(model: model, showButton: false).frame(width: MenuLayout.textWidth).frame(maxWidth: .infinity).padding(.vertical, 4))
            menu.addItem(notice)
            let setup = add("Allow Fan Control…", to: menu) { [weak model] in model?.openHelperSetup() }
            setup.image = AppModel.approvalDot()
            menu.addItem(.separator())
        }
        add("Edit Profiles…", to: menu) { [weak self] in self?.openProfiles() }
        add("Settings…", to: menu) { [weak self] in self?.openSettings() }
        let quit = add("Quit", to: menu) { [weak model] in model?.quit() }; quit.keyEquivalent = "q"
    }
    @discardableResult private func add(_ title: String, to menu: NSMenu, action: @escaping () -> Void) -> NSMenuItem {
        let id = UUID(); actions[id] = action
        let item = NSMenuItem(title: MenuLayout.compactTitle(title), action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = id
        item.toolTip = title
        item.setAccessibilityLabel(title)
        menu.addItem(item); return item
    }
    @objc private func invoke(_ item: NSMenuItem) { if let id = item.representedObject as? UUID { actions[id]?() } }
    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let child = NSMenu(title: title); child.autoenablesItems = false
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = child; menu.addItem(item); return child
    }
    private func embedded<V: View>(_ view: V, identifier: String) -> NSView {
        // NSMenuItem.view receives native mouse/keyboard events. Keep its controls
        // in the submenu's own window; never activate a separate panel/popover.
        let hosting = MenuControlHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        hosting.setAccessibilityIdentifier(identifier)
        return hosting
    }
    private func fitted<V: View>(_ view: V) -> NSView {
        let hosting = NSHostingView(rootView: view)
        let height = hosting.fittingSize.height
        hosting.sizingOptions = []
        hosting.frame.size = NSSize(width: MenuLayout.width, height: height)
        // AppKit expands this view to the menu width, including the space used by
        // native checkmarks/shortcuts. The readout centers in that actual width.
        hosting.autoresizingMask = [.width]
        return hosting
    }

}

struct ActivationMenuSummary: View {
    @Bindable var model: AppModel
    var body: some View { Text(model.activationDescription).font(.caption).foregroundStyle(.secondary)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .frame(width: MenuLayout.textWidth).frame(maxWidth: .infinity).padding(.vertical, 3) }
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
    private var clockHour: Int {
        let h = Int(untilHours) ?? 0
        return model.automation.preferences.use24HourTime ? h : h % 12 + (afternoon ? 12 : 0)
    }
    var body: some View {
        VStack(spacing: 8) {
            Picker("Activation limit", selection: $until) { Text("For").tag(false); Text("Until").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(height: 24)
            VStack(spacing: 0) {
                if until {
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            timeField("Hours", text: $untilHours, field: .hours, width: 48)
                            Text(":")
                            timeField("Minutes", text: $untilMinutes, field: .minutes, width: 48)
                            if !model.automation.preferences.use24HourTime {
                                Picker("Period", selection: $afternoon) { Text("AM").tag(false); Text("PM").tag(true) }.labelsHidden().frame(width: 60)
                            }
                        }
                        TimeDial(hour: Binding(get: { clockHour }, set: { value in afternoon = value >= 12; untilHours = String(model.automation.preferences.use24HourTime ? value : (value % 12 == 0 ? 12 : value % 12)) }), minute: Binding(get: { Int(untilMinutes) ?? 0 }, set: { untilMinutes = String(format: "%02d", $0) }), use24HourTime: model.automation.preferences.use24HourTime)
                            .fixedSize()
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow { timeField("Hours", text: $hours, field: .hours); Text("hours").frame(width: 64, alignment: .leading) }
                        GridRow { timeField("Minutes", text: $minutes, field: .minutes); Text("minutes").frame(width: 64, alignment: .leading) }
                    }.frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
                }
            }.frame(maxWidth: .infinity).frame(height: until ? 180 : 80, alignment: .center)
            Text(error ?? "").font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                .frame(height: 18, alignment: .top).accessibilityHidden(error == nil)
            Button("Continue") { apply() }.buttonStyle(.bordered).frame(height: 24)
        }.padding(10).frame(width: 220)
        .onChange(of: until) { _, _ in
            focused = .hours; error = nil
            if !model.automation.preferences.use24HourTime { let h = clockHour % 12; untilHours = String(h == 0 ? 12 : h) }
        }
    }
    private func timeField(_ label: String, text: Binding<String>, field: Field, width: CGFloat = 58) -> some View {
        TextField(label, text: text).textFieldStyle(.roundedBorder).frame(width: width).focused($focused, equals: field)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(focused == field ? Color.accentColor : .clear, lineWidth: 2))
            .onTapGesture { focused = field }.accessibilityLabel(label)
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
            NativeSearchField(placeholder: "Search running apps", text: $search).frame(height: 24)
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
            }.scrollIndicators(.hidden)
            Button("Refresh") { refresh() }.font(.caption)
        }.padding(10).frame(width: 260, height: 320)
        .onAppear { refresh() }.onChange(of: helpers) { _, _ in refresh() }
    }
    private func refresh() { processes = ProcessCatalog.list(includeHelpers: helpers) }
}

/// Embedded pickers change height as their mode changes. Unlike passive status
/// rows, they keep an intrinsic size, but only their height can resize the menu.
@MainActor final class MenuControlHostingView<Content: View>: NSHostingView<Content> {
    private var resizing = false
    override func layout() {
        super.layout()
        guard !resizing else { return }
        let height = fittingSize.height
        guard height.isFinite, height > 0, abs(frame.height - height) > 0.5 else { return }
        resizing = true
        setFrameSize(NSSize(width: frame.width, height: height))
        enclosingMenuItem?.menu?.update()
        resizing = false
    }
}
