import AppKit
import SwiftUI
import FandyCore

/// Native row selection and doubleAction avoid competing SwiftUI tap gestures.
struct ProfileSidebar: NSViewRepresentable {
    @Bindable var model: AppModel
    let profiles: [Profile]
    let selection: String
    let activeID: String?
    var exportProfile: (String) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(model: model, exportProfile: exportProfile) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = ContextTable()
        table.contextMenuForRow = { [weak coordinator = context.coordinator] row in coordinator?.menu(for: row) }
        let column = NSTableColumn(identifier: .init("profile")); table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 30; table.intercellSpacing = .init(width: 0, height: 2)
        table.style = .plain; table.backgroundColor = .clear
        table.allowsEmptySelection = false; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.activate(_:))
        table.setAccessibilityIdentifier("profiles.sidebar")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false; scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.update()
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.exportProfile = exportProfile; context.coordinator.update() }
    @MainActor final class ContextTable: NSTableView {
        var contextMenuForRow: (Int) -> NSMenu? = { _ in nil }
        override func menu(for event: NSEvent) -> NSMenu? { contextMenuForRow(row(at: convert(event.locationInWindow, from: nil))) }
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        let model: AppModel
        weak var table: NSTableView?
        private var rows: [(id: String, name: String)] = []
        private var activeID: String?
        private var updating = false
        var exportProfile: (String) -> Void
        init(model: AppModel, exportProfile: @escaping (String) -> Void = { _ in }) { self.model = model; self.exportProfile = exportProfile }
        func update() {
            guard let table else { return }
            let next = model.profiles.map { (id: $0.id, name: $0.name) }
            let changed = next.count != rows.count || zip(next, rows).contains { $0.id != $1.id || $0.name != $1.name }
            updating = true; defer { updating = false }
            if changed || activeID != model.menuSelectionID {
                rows = next; activeID = model.menuSelectionID; table.reloadData()
            }
            if let index = rows.firstIndex(where: { $0.id == model.editorSelection }), table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("profileCell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
            cell.textField?.stringValue = rows[row].name
            cell.imageView?.image = rows[row].id == activeID ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected profile") : nil
            return cell
        }
        private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView(); cell.identifier = identifier
            let label = NSTextField(labelWithString: ""); label.lineBreakMode = .byTruncatingTail
            let check = NSImageView(); check.imageScaling = .scaleProportionallyDown
            label.translatesAutoresizingMaskIntoConstraints = false; check.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label); cell.addSubview(check); cell.textField = label; cell.imageView = check
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                check.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 6), check.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                check.centerYAnchor.constraint(equalTo: cell.centerYAnchor), check.widthAnchor.constraint(equalToConstant: 12), check.heightAnchor.constraint(equalToConstant: 12)
            ])
            return cell
        }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !model.savingCollection && !model.isQuitting }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, !model.savingCollection, !model.isQuitting, let table, rows.indices.contains(table.selectedRow) else { return }
            model.editorSelection = rows[table.selectedRow].id
        }
        func menu(for row: Int) -> NSMenu? {
            guard rows.indices.contains(row), let profile = model.profiles.first(where: { $0.id == rows[row].id }) else { return nil }
            let menu = NSMenu(); menu.autoenablesItems = false
            let rename = NSMenuItem(title: "Rename…", action: #selector(rename(_:)), keyEquivalent: "")
            rename.target = self; rename.representedObject = profile.id
            rename.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
            rename.isEnabled = !profile.protected && !model.savingCollection && !model.isQuitting
            menu.addItem(rename)
            for (title, action, symbol, allowed) in [
                ("Duplicate", #selector(duplicate(_:)), "square.on.square", true),
                ("Export…", #selector(export(_:)), "square.and.arrow.up", true),
                ("Remove", #selector(remove(_:)), "trash", !profile.bundled)
            ] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self; item.representedObject = profile.id
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                item.isEnabled = allowed && !model.savingCollection && !model.isQuitting
                menu.addItem(item)
            }
            return menu
        }
        @objc private func rename(_ item: NSMenuItem) {
            guard let id = item.representedObject as? String else { return }; model.requestRename(id)
        }
        @objc private func duplicate(_ item: NSMenuItem) {
            guard let id = item.representedObject as? String else { return }; model.duplicate(id)
        }
        @objc private func remove(_ item: NSMenuItem) {
            guard let id = item.representedObject as? String else { return }; model.delete(id)
        }
        @objc private func export(_ item: NSMenuItem) {
            guard !model.savingCollection, !model.isQuitting, let id = item.representedObject as? String,
                  model.profiles.contains(where: { $0.id == id }) else { return }; exportProfile(id)
        }
        @objc func activate(_ sender: NSTableView) { activateRow(sender.clickedRow) }
        func activateRow(_ row: Int) {
            guard !model.savingCollection, !model.isQuitting, rows.indices.contains(row) else { return }
            let id = rows[row].id; model.editorSelection = id; model.select(id)
        }
    }
}
