import AppKit

/// Split view com a cor do divisor seguindo o tema.
final class ThemedSplitView: NSSplitView {
    var themedDividerColor: NSColor = .separatorColor { didSet { needsDisplay = true } }
    override var dividerColor: NSColor { themedDividerColor }
}

private final class SidebarOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?() } else { super.keyDown(with: event) }
    }
}

private final class SidebarRowView: NSTableRowView {
    var fill: NSColor = .selectedContentBackgroundColor
    override func drawSelection(in dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

/// Barra lateral no estilo do Explorador do VS Code: documentos abertos e recentes.
final class SidebarView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    final class Section {
        let id: String
        let title: String
        var items: [Item] = []
        init(id: String, title: String) { self.id = id; self.title = title }
    }

    final class Item {
        let url: URL?
        weak var doc: MarkdownDocument?
        let name: String
        let detail: String
        let edited: Bool
        init(url: URL?, doc: MarkdownDocument?, name: String, detail: String, edited: Bool) {
            self.url = url; self.doc = doc; self.name = name; self.detail = detail; self.edited = edited
        }
    }

    weak var currentDocument: MarkdownDocument? { didSet { selectCurrent() } }

    private let search = NSSearchField()
    private let scroll = NSScrollView()
    private let outline = SidebarOutlineView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let footerLine = NSBox()
    private let openButton = NSButton()
    private let newButton = NSButton()
    private var topConstraint: NSLayoutConstraint!
    private let openSection = Section(id: "abertos", title: "Abertos")
    private let recentSection = Section(id: "recentes", title: "Recentes")
    private var visibleSections: [Section] = []
    private var palette = ReaderTheme.claro.palette
    private var reloadPending = false
    private var restoringExpansion = false
    private var observer: NSObjectProtocol?

    var topInset: CGFloat = 10 { didSet { topConstraint.constant = topInset } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        build()
        observer = NotificationCenter.default.addObserver(forName: .marcadoDocumentsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleReload()
        }
        registerForDraggedTypes([.fileURL])
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func build() {
        search.placeholderString = "Filtrar documentos"
        search.controlSize = .regular
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        search.focusRingType = .none

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .plain
        outline.rowSizeStyle = .custom
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        outline.indentationPerLevel = 4
        outline.backgroundColor = .clear
        outline.focusRingType = .none
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.onReturn = { [weak self] in self?.openSelected() }
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        scroll.documentView = outline
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 6, right: 0)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.alignment = .center

        footerLine.boxType = .custom
        footerLine.borderWidth = 0

        for (b, title, symbol, action) in [(openButton, "Abrir documento…", "folder", #selector(NSDocumentController.openDocument(_:))),
                                           (newButton, "", "plus", #selector(NSDocumentController.newDocument(_:)))] {
            b.isBordered = false
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title.isEmpty ? "Novo documento" : title)
            b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            b.title = title
            b.font = .systemFont(ofSize: 12)
            b.target = nil
            b.action = action
        }
        newButton.toolTip = "Novo documento (⌘N)"
        openButton.toolTip = "Abrir documento (⌘O)"

        for v in [search, scroll, emptyLabel, footerLine, openButton, newButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        topConstraint = search.topAnchor.constraint(equalTo: topAnchor, constant: topInset)
        NSLayoutConstraint.activate([
            topConstraint,
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footerLine.topAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            emptyLabel.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 28),
            footerLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerLine.heightAnchor.constraint(equalToConstant: 1),
            footerLine.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -34),
            openButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            openButton.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -17),
            newButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            newButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
        ])
    }

    // MARK: - Tema

    static func background(_ p: Palette, dark: Bool) -> NSColor {
        p.bg.blended(withFraction: dark ? 0.045 : 0.04, of: dark ? .white : p.text) ?? p.bg
    }

    func apply(_ p: Palette, dark: Bool) {
        palette = p
        layer?.backgroundColor = Self.background(p, dark: dark).cgColor
        footerLine.fillColor = p.border
        emptyLabel.textColor = p.muted
        for b in [openButton, newButton] {
            b.contentTintColor = p.muted
            if !b.title.isEmpty {
                b.attributedTitle = NSAttributedString(string: b.title, attributes: [.foregroundColor: p.text, .font: NSFont.systemFont(ofSize: 12)])
            }
        }
        reload()
    }

    // MARK: - Dados

    func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.async { [weak self] in
            self?.reloadPending = false
            self?.reload()
        }
    }

    @objc private func searchChanged() { reload() }

    func reload() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces)
        func match(_ name: String, _ path: String) -> Bool {
            q.isEmpty
                || name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || path.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        let docs = SessionStore.orderedDocuments()
        let openPaths = Set(docs.compactMap { $0.fileURL?.standardizedFileURL.path })
        openSection.items = docs.compactMap { d in
            let name = d.displayName ?? "Sem título"
            guard match(name, d.fileURL?.path ?? "") else { return nil }
            let detail = d.fileURL.map { Self.folder(of: $0) } ?? "rascunho"
            return Item(url: d.fileURL, doc: d, name: name, detail: detail, edited: d.isDocumentEdited)
        }
        recentSection.items = SessionStore.recentURLs
            .filter { !openPaths.contains($0.standardizedFileURL.path) }
            .compactMap { url in
                guard match(url.lastPathComponent, url.path) else { return nil }
                return Item(url: url, doc: nil, name: url.lastPathComponent, detail: Self.folder(of: url), edited: false)
            }
        visibleSections = [openSection, recentSection].filter { !$0.items.isEmpty }
        outline.reloadData()

        restoringExpansion = true
        let collapsed = Settings.collapsedSidebarSections
        for s in visibleSections {
            if collapsed.contains(s.id) && q.isEmpty { outline.collapseItem(s) } else { outline.expandItem(s) }
        }
        restoringExpansion = false

        emptyLabel.stringValue = q.isEmpty ? "Nenhum documento recente" : "Nada encontrado"
        emptyLabel.isHidden = !visibleSections.isEmpty
        selectCurrent()
    }

    /// Só o nome da pasta, como o VS Code; o caminho completo fica na dica ao passar o mouse.
    static func folder(of url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent
    }

    private func selectCurrent() {
        guard let cur = currentDocument, let item = openSection.items.first(where: { $0.doc === cur }) else {
            outline.deselectAll(nil)
            return
        }
        let row = outline.row(forItem: item)
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }

    // MARK: - Abrir

    @objc private func clicked() {
        let row = outline.clickedRow
        guard row >= 0 else { return }
        let obj = outline.item(atRow: row)
        if let s = obj as? Section {
            if outline.isItemExpanded(s) { outline.collapseItem(s) } else { outline.expandItem(s) }
        } else if let item = obj as? Item {
            open(item)
        }
    }

    private func openSelected() {
        guard outline.selectedRow >= 0, let item = outline.item(atRow: outline.selectedRow) as? Item else { return }
        open(item)
    }

    private func open(_ item: Item) {
        if let d = item.doc, NSDocumentController.shared.documents.contains(where: { $0 === d }) {
            d.showWindows()
            return
        }
        guard let url = item.url else { return }
        Self.open([url])
    }

    static func open(_ urls: [URL]) {
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error {
                    if !FileManager.default.fileExists(atPath: url.path) { SessionStore.removeRecent(url) }
                    NSApp.presentError(error)
                }
            }
        }
    }

    // MARK: - Arrastar arquivos

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        Self.open(urls)
        return !urls.isEmpty
    }

    // MARK: - NSOutlineView

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return visibleSections.count }
        return (item as? Section)?.items.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let s = item as? Section { return s.items[index] }
        return visibleSections[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is Section }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { item is Section ? 28 : 26 }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { item is Item }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let r = SidebarRowView()
        r.fill = palette.selection
        return r
    }

    func outlineViewItemDidExpand(_ notification: Notification) { saveExpansion(notification, collapsed: false) }
    func outlineViewItemDidCollapse(_ notification: Notification) { saveExpansion(notification, collapsed: true) }

    private func saveExpansion(_ n: Notification, collapsed: Bool) {
        guard !restoringExpansion, search.stringValue.isEmpty,
              let s = n.userInfo?["NSObject"] as? Section else { return }
        var set = Settings.collapsedSidebarSections
        if collapsed { set.insert(s.id) } else { set.remove(s.id) }
        Settings.collapsedSidebarSections = set
    }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = NSTableCellView()
        if let s = item as? Section {
            let title = label("", size: 11, weight: .semibold, color: palette.muted)
            title.attributedStringValue = NSAttributedString(string: s.title.uppercased(), attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: palette.muted, .kern: 0.6,
            ])
            let count = label("\(s.items.count)", size: 11, color: palette.muted.withAlphaComponent(0.7))
            cell.addSubview(title)
            cell.addSubview(count)
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                title.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: 1),
                count.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 6),
                count.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            ])
            return cell
        }
        guard let it = item as? Item else { return nil }
        let isCurrent = it.doc != nil && it.doc === currentDocument
        let symbol = it.url == nil ? "square.and.pencil" : (it.url!.pathExtension.lowercased() == "txt" ? "doc.plaintext" : "doc.text")
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        icon.contentTintColor = isCurrent ? palette.accent : palette.muted
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = label(it.name, size: 13, weight: isCurrent ? .medium : .regular, color: palette.text)
        let detail = label(it.detail, size: 11, color: palette.muted)
        let dot = label("●", size: 8, color: palette.accent)
        dot.isHidden = !it.edited
        dot.toolTip = "Alterações ainda não salvas em arquivo"
        name.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        name.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dot.setContentCompressionResistancePriority(.required, for: .horizontal)
        for v in [icon, name, detail, dot] { cell.addSubview(v) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            detail.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 6),
            detail.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: dot.leadingAnchor, constant: -6),
            dot.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            dot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.toolTip = it.url?.path ?? "Rascunho não salvo (fica guardado mesmo sem salvar)"
        return cell
    }

    // MARK: - Menu de contexto

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outline.clickedRow
        guard row >= 0 else { return }
        let obj = outline.item(atRow: row)
        func add(_ title: String, _ action: Selector, _ rep: Any?) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            i.representedObject = rep
            menu.addItem(i)
        }
        if let s = obj as? Section {
            if s === recentSection { add("Limpar recentes", #selector(clearRecents(_:)), nil) }
            return
        }
        guard let it = obj as? Item else { return }
        add("Abrir", #selector(menuOpen(_:)), it)
        if it.url != nil || it.doc != nil { add("Duplicar", #selector(duplicateItem(_:)), it) }
        if it.url != nil {
            add("Mostrar no Finder", #selector(revealInFinder(_:)), it)
            add("Copiar caminho", #selector(copyPath(_:)), it)
        }
        menu.addItem(.separator())
        if it.doc != nil {
            add("Fechar", #selector(closeDocument(_:)), it)
        } else {
            add("Remover dos recentes", #selector(removeRecent(_:)), it)
            add("Limpar recentes", #selector(clearRecents(_:)), nil)
        }
    }

    @objc private func menuOpen(_ sender: NSMenuItem) { (sender.representedObject as? Item).map(open) }

    /// Arquivo: cópia salva ao lado ("Nome cópia.md"), aberta e pronta para renomear.
    /// Rascunho: vira outro rascunho, como Arquivo > Duplicar.
    @objc private func duplicateItem(_ sender: NSMenuItem) {
        guard let it = sender.representedObject as? Item else { return }
        if let d = it.doc, NSDocumentController.shared.documents.contains(where: { $0 === d }) {
            d.duplicate(nil)
        } else if let url = it.url {
            MarkdownDocument.duplicateFile(url)
        }
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let url = (sender.representedObject as? Item)?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let url = (sender.representedObject as? Item)?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    @objc private func closeDocument(_ sender: NSMenuItem) {
        (sender.representedObject as? Item)?.doc?.windowControllers.first?.window?.performClose(nil)
    }

    @objc private func removeRecent(_ sender: NSMenuItem) {
        guard let url = (sender.representedObject as? Item)?.url else { return }
        SessionStore.removeRecent(url)
    }

    @objc private func clearRecents(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
}
