import SwiftUI
import AppKit
import FandyCore
import Observation

struct StatusItemPresentation: Equatable {
    let attention: Bool
    let tooltip: String
}

/// AppKit provides actual hierarchical menus with embedded controls; the editor remains SwiftUI.
@MainActor final class StatusMenu: NSObject, NSMenuDelegate {
    let model: AppModel
    let item: NSStatusItem?
    var openProfiles: () -> Void = {}
    var openSettings: () -> Void = {}
    var openHelperSetup: () -> Void = {}
    private var lastPresentation: StatusItemPresentation?
    private let onPresentation: ((StatusItemPresentation) -> Void)?
    private var actions: [UUID: () -> Void] = [:]
    private var profileRows: [String: NSMenuItem] = [:]
    private var timingRow: NSMenuItem?
    private var customSpeedRow: NSMenuItem?
    private(set) var isOpen = false
    init(model: AppModel, install: Bool = true, onPresentation: ((StatusItemPresentation) -> Void)? = nil) {
        self.model = model; self.onPresentation = onPresentation; item = install ? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) : nil; super.init()
        let menu = NSMenu(); menu.delegate = self; item?.menu = menu
        item?.button?.image = NSImage(systemSymbolName: "fan", accessibilityDescription: "Fandy")
        item?.button?.imagePosition = .imageLeading
        observePresentation()
    }
    private func observePresentation() {
        withObservationTracking { updateTitle() } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observePresentation() }
        }
    }
    func toggle() {
        if isOpen { item?.menu?.cancelTracking() }
        else { item?.button?.performClick(nil) }
    }
    private func refreshSelection() {
        for (id, row) in profileRows {
            let next: NSControl.StateValue = model.menuSelectionID == id ? .on : .off
            if row.state != next { row.state = next; if isOpen { row.view?.needsDisplay = true } }
        }
        timingRow?.isEnabled = model.canSetActivationLimit
        customSpeedRow?.state = model.isCustomFanSpeedActive ? .on : .off
        customSpeedRow?.isEnabled = model.canActivateCustomFanSpeed
    }
    func updateTitle() {
        refreshSelection()
        let next = StatusItemPresentation(attention: model.needsHelperAttention,
            tooltip: model.needsHelperAttention ? model.helperSetupMessage : model.statusText + " · " + model.activationDescription)
        guard next != lastPresentation else { return }
        lastPresentation = next; onPresentation?(next)
        item?.button?.attributedTitle = NSAttributedString(string: next.attention ? "●" : "",
            attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: 8)])
        item?.button?.setAccessibilityLabel(next.attention ? "Fandy — fan control unavailable" : "Fandy")
        item?.button?.toolTip = next.tooltip
    }
    func menuWillOpen(_ menu: NSMenu) { isOpen = true; rebuild(menu) }
    func menuDidClose(_ menu: NSMenu) { isOpen = false }
    func rebuild(_ menu: NSMenu) {
        actions.removeAll(); profileRows.removeAll(); customSpeedRow = nil; timingRow = nil; menu.removeAllItems(); menu.autoenablesItems = false; menu.minimumWidth = MenuLayout.width
        for profile in model.profiles where profile.showInMenuBar {
            let row = add(profile.name, to: menu) { [weak model] in model?.select(profile.id) }
            if profile.kind != .system && model.needsHelperAttention { row.image = AppModel.approvalDot() }
            row.isEnabled = model.canActivate(profile)
            profileRows[profile.id] = row; row.state = model.menuSelectionID == profile.id ? .on : .off
            row.toolTip = profile.kind != .system && model.needsHelperAttention ? model.helperSetupMessage : model.activationConditionNote(profile) ?? model.eligibility(profile).reason ?? profile.name
        }
        menu.addItem(.separator())
        if model.automation.preferences.showCustomFanSpeed {
            let speed = submenu("Custom Fan Speed", in: menu)
            customSpeedRow = menu.items.last
            customSpeedRow?.state = model.isCustomFanSpeedActive ? .on : .off
            customSpeedRow?.isEnabled = model.canActivateCustomFanSpeed
            if model.needsHelperAttention { customSpeedRow?.image = AppModel.approvalDot() }
            let controls = NSMenuItem()
            controls.view = CustomFanSpeedMenuView(model: model)
            controls.view?.setAccessibilityIdentifier("activation.fan-speed")
            speed.addItem(controls)
            let chosen = model.automation.preferences.customFanSpeedDurationMinutes
            let indefinite = model.automation.preferences.customFanSpeedIndefinite
            let duration = submenu(indefinite ? "Indefinitely" : "For " + CustomActivationPicker.durationLabel(chosen), in: speed)
            let forever = add("Indefinitely", to: duration) { [weak model] in model?.setCustomFanSpeedLimit(seconds: nil) }
            forever.state = indefinite ? .on : .off
            let presets = Array(Set([5, 10, 15, 30, 60, 120, 240, 360, 720, 1440, chosen])).sorted()
            for value in presets {
                let row = add(CustomActivationPicker.durationLabel(value), to: duration) { [weak model] in
                    model?.setCustomFanSpeedDuration(minutes: value)
                }
                row.tag = value; row.state = !indefinite && chosen == value ? .on : .off
            }
            duration.addItem(.separator())
            let other = submenu("Other…", in: duration)
            addTimePicker(to: other, root: menu, destination: .customFanSpeed, identifier: "activation.fan-speed-duration")
        }
        if model.automation.preferences.showActivationTiming {
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
            addTimePicker(to: time, root: menu, destination: .currentProfile, identifier: "activation.time")
            let applications = submenu("While App Is Running", in: timing)
            let appControls = NSMenuItem()
            appControls.view = embedded(ProcessPicker(model: model, close: { [weak menu] in menu?.cancelTracking() }), identifier: "activation.application")
            applications.addItem(appControls)
            timing.addItem(.separator())
            let forever = add("Until Changed", to: timing) { [weak model] in model?.activateForever() }
            if case .forever = model.manualIntent?.limit, model.awaitingApplicationID == nil, model.watchedApplications.isEmpty { forever.state = .on }
        }
        if (model.manualIntent.map { $0.limit != .forever } ?? false) || !model.watchedApplications.isEmpty || model.awaitingApplicationID != nil || model.scheduledPeriodID != nil {
            let explanation = NSMenuItem(); explanation.view = fitted(ActivationMenuSummary(model: model)); menu.addItem(explanation)
        }
        if model.showsCancellation {
            let title = model.cancellationTitle
            let row = add(title, to: menu) { [weak model] in model?.cancelActivation() }
            if MenuLayout.titleWidth(title) > MenuLayout.nativeTitleWidth {
                row.view = fitted(WrappedMenuAction(title: title) { [weak model, weak menu] in
                    menu?.cancelTracking(); model?.cancelActivation()
                })
            }
        }
        menu.addItem(.separator())
        let status = NSMenuItem(); status.view = fitted(FanMenuStatus(model: model)); menu.addItem(status)
        menu.addItem(.separator())
        if model.needsHelperAttention {
            let notice = NSMenuItem()
            notice.view = fitted(HelperApprovalNotice(model: model, showButton: false).frame(width: MenuLayout.textWidth).frame(maxWidth: .infinity).padding(.vertical, 4))
            menu.addItem(notice)
            if model.shouldPresentHelperApproval {
                let setup = add("Allow Fan Control…", to: menu) { [weak self] in self?.openHelperSetup() }
                setup.image = AppModel.approvalDot()
            } else {
                add("Retry Fan Helper", to: menu) { [weak model] in model?.retryFanHelper() }
                add("Export Diagnostics…", to: menu) { [weak model] in model?.exportDiagnostics() }
            }
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
    private func addTimePicker(to submenu: NSMenu, root: NSMenu, destination: CustomActivationPicker.Destination, identifier: String) {
        let controls = NSMenuItem()
        controls.view = embedded(CustomActivationPicker(model: model, destination: destination, close: { [weak root] in root?.cancelTracking() }), identifier: identifier)
        submenu.addItem(controls)
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
    enum Destination { case currentProfile, customFanSpeed }
    let destination: Destination
    let initialDurationMinutes: Int
    init(model: AppModel, destination: Destination = .currentProfile, close: @escaping () -> Void) {
        self.model = model; self.destination = destination; self.close = close
        initialDurationMinutes = destination == .customFanSpeed ? model.automation.preferences.customFanSpeedDurationMinutes : 60
        _hours = State(initialValue: String(initialDurationMinutes / 60))
        _minutes = State(initialValue: String(initialDurationMinutes % 60))
    }
    static func durationLabel(_ value: Int) -> String {
        let h = value / 60, m = value % 60
        let hour = "\(h) \(h == 1 ? "hour" : "hours")"
        let minute = "\(m) \(m == 1 ? "minute" : "minutes")"
        if h == 0 { return minute }
        if m == 0 { return hour }
        return hour + " " + minute
    }
    /// Both For and Until use this validation/dispatch; only the destination
    /// differs, keeping the clock, fields and presentation in one shared view.
    @discardableResult func applyInterval(_ seconds: Double) -> Bool {
        guard seconds.isFinite, seconds > 0, seconds <= 31 * 86400 else { return false }
        if destination == .customFanSpeed { return model.setCustomFanSpeedLimit(seconds: seconds) }
        model.activateFor(seconds: seconds)
        return model.draftError == nil
    }
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
            guard applyInterval(next.timeIntervalSince(model.wallClock())) else { error = model.draftError ?? "Select an available profile."; return }
        } else {
            guard let h = integer(hours), let m = integer(minutes), (0...743).contains(h), (0...59).contains(m), h + m > 0 else { error = "Enter a positive duration."; return }
            guard applyInterval(Double(h*3600+m*60)) else { error = model.draftError ?? "Select an available profile."; return }
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
