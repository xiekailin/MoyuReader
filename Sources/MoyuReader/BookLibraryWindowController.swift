import AppKit
import MoyuReaderCore

@MainActor
final class BookLibraryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: BookLibraryStore
    private let onOpen: (URL) -> Void

    private let tableView = NSTableView()
    private let openButton = NSButton()
    private let removeButton = NSButton()
    private let revealButton = NSButton()

    init(store: BookLibraryStore, onOpen: @escaping (URL) -> Void) {
        self.store = store
        self.onOpen = onOpen

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "书库"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        window.contentView = makeContentView()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func reload() {
        tableView.reloadData()
        updateButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.catalog.entries.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard store.catalog.entries.indices.contains(row) else {
            return nil
        }

        let entry = store.catalog.entries[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = identifier

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingMiddle
        textField.maximumNumberOfLines = 1
        textField.font = .systemFont(ofSize: 13)
        cell.textField = textField

        if textField.superview == nil {
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        switch tableColumn?.identifier.rawValue {
        case "title":
            textField.stringValue = entry.title
        case "lastOpened":
            textField.stringValue = Self.dateFormatter.string(from: entry.lastOpened)
        default:
            textField.stringValue = entry.path
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    private func makeContentView() -> NSView {
        let root = NSView()

        let titleLabel = NSTextField(labelWithString: "书库")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: "这里会记录你打开过的 EPUB，之后可以直接切换。")
        subtitleLabel.textColor = .secondaryLabelColor

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        tableView.addTableColumn(makeColumn(id: "title", title: "书名", width: 240))
        tableView.addTableColumn(makeColumn(id: "path", title: "文件位置", width: 340))
        tableView.addTableColumn(makeColumn(id: "lastOpened", title: "最近打开", width: 140))
        tableView.headerView = NSTableHeaderView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(openSelectedBook)
        tableView.target = self
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 28
        scrollView.documentView = tableView

        openButton.title = "打开"
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openSelectedBook)

        revealButton.title = "在访达中显示"
        revealButton.bezelStyle = .rounded
        revealButton.target = self
        revealButton.action = #selector(revealSelectedBook)

        removeButton.title = "移除记录"
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeSelectedBook)

        let buttonRow = NSStackView(views: [openButton, revealButton, removeButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        let stack = NSStackView(views: [titleLabel, subtitleLabel, scrollView, buttonRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            scrollView.heightAnchor.constraint(equalToConstant: 300)
        ])

        return root
    }

    private func makeColumn(id: String, title: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = 80
        return column
    }

    @objc private func openSelectedBook() {
        guard let entry = selectedEntry else {
            return
        }

        guard FileManager.default.fileExists(atPath: entry.path) else {
            showMissingFileAlert(for: entry)
            return
        }

        onOpen(URL(fileURLWithPath: entry.path))
    }

    @objc private func revealSelectedBook() {
        guard let entry = selectedEntry else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
    }

    @objc private func removeSelectedBook() {
        guard let entry = selectedEntry else {
            return
        }

        store.remove(path: entry.path)
        reload()
    }

    private var selectedEntry: BookLibraryEntry? {
        let row = tableView.selectedRow
        guard store.catalog.entries.indices.contains(row) else {
            return nil
        }

        return store.catalog.entries[row]
    }

    private func updateButtons() {
        let hasSelection = selectedEntry != nil
        openButton.isEnabled = hasSelection
        revealButton.isEnabled = hasSelection
        removeButton.isEnabled = hasSelection
    }

    private func showMissingFileAlert(for entry: BookLibraryEntry) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "找不到这本书"
        alert.informativeText = "文件可能已经移动或删除：\n\(entry.path)"
        alert.addButton(withTitle: "移除记录")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            store.remove(path: entry.path)
            reload()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
