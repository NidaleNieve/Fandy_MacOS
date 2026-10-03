import AppKit
import SwiftUI
import FandyCore

/// Native row selection and doubleAction avoid competing SwiftUI tap gestures.
struct ProfileSidebar: NSViewRepresentable {
    @Bindable var model: AppModel
    let profiles: [Profile]
    let selection: String
    let activeID: String?
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        let column = NSTableColumn(identifier: .init("profile")); table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 30; table.intercellSpacing = .init(width: 0, height: 2)
        table.style = .sourceList
        table.allowsEmptySelection = false; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.activate(_:))
        table.setAccessibilityIdentifier("profiles.sidebar")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.update()
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.update() }
    @MainActor final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        let model: AppModel
        weak var table: NSTableView?
        private var rows: [(id: String, name: String)] = []
        private var activeID: String?
        private var updating = false
        init(model: AppModel) { self.model = model }
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
        @objc func activate(_ sender: NSTableView) { activateRow(sender.clickedRow) }
        func activateRow(_ row: Int) {
            guard !model.savingCollection, !model.isQuitting, rows.indices.contains(row) else { return }
            let id = rows[row].id; model.editorSelection = id; model.select(id)
        }
    }
}
