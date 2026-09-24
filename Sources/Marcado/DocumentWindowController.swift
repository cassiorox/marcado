import AppKit
import UniformTypeIdentifiers

private extension NSToolbarItem.Identifier {
    static let sidebar = NSToolbarItem.Identifier("barraLateral")
    static let mode = NSToolbarItem.Identifier("modo")
    static let bold = NSToolbarItem.Identifier("negrito")
    static let italic = NSToolbarItem.Identifier("italico")
    static let strike = NSToolbarItem.Identifier("riscado")
    static let highlight = NSToolbarItem.Identifier("destaque")
    static let heading = NSToolbarItem.Identifier("titulo")
    static let link = NSToolbarItem.Identifier("link")
    static let image = NSToolbarItem.Identifier("imagem")
    static let code = NSToolbarItem.Identifier("codigo")
    static let quote = NSToolbarItem.Identifier("citacao")
    static let bullet = NSToolbarItem.Identifier("lista")
    static let numbered = NSToolbarItem.Identifier("numerada")
    static let task = NSToolbarItem.Identifier("tarefas")
    static let table = NSToolbarItem.Identifier("tabela")
    static let appearance = NSToolbarItem.Identifier("aparencia")
    static let focus = NSToolbarItem.Identifier("foco")
    static let export = NSToolbarItem.Identifier("exportar")
}

/// Janela de um documento: barra de ferramentas, editor e visualização lado a lado, rodapé.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate,
                                      NSToolbarDelegate, NSSplitViewDelegate, NSMenuItemValidation {
    let outerSplit = ThemedSplitView()
    let sidebar = SidebarView(frame: .zero)
    let splitView = ThemedSplitView()
    let editorScroll: NSScrollView
    let textView: MarkdownTextView
    let highlighter = SyntaxHighlighter()
    let preview = PreviewView(frame: .zero)
    let statusBar = StatusBarView(frame: .zero)
    private var statusHeight: NSLayoutConstraint!

    private(set) var mode: ViewMode = Settings.viewMode
    private(set) var focusMode = false
    private var modeBeforeFocus: ViewMode = .split
    private weak var modeGroup: NSToolbarItemGroup?
    private var suppressEditorSyncUntil = Date.distantPast
    private var statusWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var didInitialLayout = false

    private var doc: MarkdownDocument? { document as? MarkdownDocument }

    init(text: String, isNew: Bool) {
        (editorScroll, textView) = MarkdownTextView.make()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 520, height: 360)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "MarcadoDocumento"
        window.isRestorable = false
        super.init(window: window)
        shouldCascadeWindows = true
        window.delegate = self
        buildLayout(in: window)
        buildToolbar(in: window)

        textView.textStorage?.delegate = highlighter
        textView.delegate = self
        if MarkdownTextView.attachmentDirectoryProvider == nil {
            // Imagem colada: `anexos/` ao lado do documento salvo; rascunho usa a pasta do app.
            MarkdownTextView.attachmentDirectoryProvider = { tv in
                if let dir = MarkdownTextView.documentFolderProvider?(tv) { return dir.appendingPathComponent("anexos", isDirectory: true) }
                return SessionStore.directory.appendingPathComponent("Anexos", isDirectory: true)
            }
            MarkdownTextView.documentFolderProvider = { tv in
                (tv.window?.windowController as? DocumentWindowController)?.doc?.fileURL?.deletingLastPathComponent()
            }
        }
        textView.onEscape = { [weak self] in
            guard let self, self.focusMode else { return false }
            self.toggleFocusMode(nil)
            return true
        }
        preview.onUserScroll = { [weak self] line in
            guard let self, self.mode == .split, Settings.syncScroll else { return }
            self.suppressEditorSyncUntil = Date().addingTimeInterval(0.3)
            self.textView.scrollTo(line: line)
        }
        preview.onLoad = { [weak self] in self?.applySettings() }

        applySettings()
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.invalidateLines()
        highlighter.highlightAll(textView.textStorage!)

        // Documento novo abre no modo dividido; existente, no último modo usado.
        setMode(isNew && Settings.viewMode == .reader ? .split : Settings.viewMode, persist: false)
        preview.render(text, line: 0, immediate: true)
        updateStatusNow()

        editorScroll.contentView.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                object: editorScroll.contentView, queue: .main) { [weak self] _ in
            self?.editorDidScroll()
        })
        observers.append(NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        })
        window.center()
        // Garante que o documento abre no topo depois do primeiro layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.suppressEditorSyncUntil = Date().addingTimeInterval(0.3)
            self.editorScroll.contentView.scroll(to: .zero)
            self.editorScroll.reflectScrolledClipView(self.editorScroll.contentView)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Layout

    private func buildLayout(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.addArrangedSubview(editorScroll)
        splitView.addArrangedSubview(preview)

        outerSplit.isVertical = true
        outerSplit.dividerStyle = .thin
        outerSplit.delegate = self
        outerSplit.translatesAutoresizingMaskIntoConstraints = false
        outerSplit.addArrangedSubview(sidebar)
        outerSplit.addArrangedSubview(splitView)
        outerSplit.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        outerSplit.setHoldingPriority(NSLayoutConstraint.Priority(240), forSubviewAt: 1)
        content.addSubview(outerSplit)

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusBar)
        statusHeight = statusBar.heightAnchor.constraint(equalToConstant: StatusBarView.height)

        NSLayoutConstraint.activate([
            outerSplit.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            outerSplit.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            outerSplit.topAnchor.constraint(equalTo: content.topAnchor),
            outerSplit.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusHeight,
        ])
    }

    func splitView(_ sv: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        if sv === outerSplit { return max(proposed, 180) }
        // Com um painel escondido o divisor vai até a borda; o limite vale só no modo dividido.
        return mode == .split ? max(proposed, 240) : proposed
    }

    func splitView(_ sv: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        if sv === outerSplit { return min(proposed, 480, sv.bounds.width - 320) }
        return mode == .split ? min(proposed, sv.bounds.width - 240) : proposed
    }

    func splitView(_ sv: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        !(sv === outerSplit && view === sidebar)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard (notification.object as? NSSplitView) === outerSplit, !sidebar.isHidden,
              NSApp.currentEvent?.type == .leftMouseDragged else { return }
        Settings.sidebarWidth = sidebar.frame.width
    }

    /// Mostra ou esconde a barra lateral e aplica a largura lembrada.
    func applySidebarVisibility() {
        let hide = !Settings.showSidebar || focusMode
        if sidebar.isHidden != hide {
            sidebar.isHidden = hide
            outerSplit.adjustSubviews()
        }
        if !hide, abs(sidebar.frame.width - Settings.sidebarWidth) > 1 {
            outerSplit.setPosition(Settings.sidebarWidth, ofDividerAt: 0)
        }
    }

    @objc func toggleDocumentSidebar(_ sender: Any?) {
        if focusMode { toggleFocusMode(nil) }
        Settings.showSidebar.toggle()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applySidebarVisibility()
        relayoutPanes()
        SessionStore.scheduleSave()
    }

    /// Refaz o layout dos painéis. Necessário ao voltar de uma aba em segundo plano: o split view
    /// pode ter ficado com frames velhos (painel escondido ainda ocupando espaço, editor largo demais).
    private func relayoutPanes() {
        outerSplit.adjustSubviews()
        placeDivider(centerIfSplit: false)
        textView.fitWidthToClip()
        textView.updateInsets()
        redrawPanes()
    }

    /// O NSSplitView não apaga o divisor antigo quando um painel some (ficava uma linha cinza no
    /// meio do editor no modo "Só editor"); força o redesenho de tudo.
    private func redrawPanes() {
        outerSplit.needsDisplay = true
        splitView.needsDisplay = true
        editorScroll.needsDisplay = true
        textView.needsDisplay = true
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        doc?.undoManager
    }

    func windowDidResize(_ notification: Notification) {
        textView.fitWidthToClip()
        textView.updateInsets()
    }

    // MARK: - Configurações (tema, fontes)

    func applySettings() {
        guard let window else { return }
        let chosen = Settings.theme
        if chosen == .automatico {
            window.appearance = nil
        } else {
            window.appearance = NSAppearance(named: chosen.isDark ? .darkAqua : .aqua)
        }
        let theme = chosen.resolved(for: window.effectiveAppearance)
        let p = theme.palette

        let font = Settings.editorFont.font(size: CGFloat(Settings.editorSize))
        highlighter.configure(palette: p, font: font, spacing: Settings.lineSpacing)
        textView.backgroundColor = p.bg
        editorScroll.backgroundColor = p.bg
        textView.insertionPointColor = p.accent
        textView.selectedTextAttributes = [.backgroundColor: p.selection]
        textView.linkTextAttributes = [.foregroundColor: p.link]
        textView.typingAttributes = highlighter.baseAttributes
        textView.font = font
        if let ts = textView.textStorage { highlighter.highlightAll(ts) }
        textView.typewriter = Settings.typewriter && mode != .reader
        textView.maxLineWidth = focusMode ? 700 : 780

        preview.setBackground(p.bg)
        preview.apply(settings: Settings.previewSettings(appearance: window.effectiveAppearance))
        statusBar.apply(p)
        statusBar.isHidden = !Settings.showStatusBar || focusMode
        splitView.themedDividerColor = p.border
        outerSplit.themedDividerColor = p.border
        sidebar.apply(p, dark: theme.isDark)
        applySidebarVisibility()
        statusHeight.constant = statusBar.isHidden ? 0 : StatusBarView.height
    }

    // MARK: - Texto

    func replaceText(_ text: String) {
        textView.string = text
        textView.invalidateLines()
        if let ts = textView.textStorage { highlighter.highlightAll(ts) }
        preview.render(text, line: textView.topVisibleLine(), immediate: true)
        updateStatusNow()
    }

    func documentURLChanged() {
        preview.baseURL = doc?.fileURL?.deletingLastPathComponent()
        if mode != .editor { preview.render(textView.string, line: nil, immediate: true) }
    }

    override var document: AnyObject? {
        didSet {
            sidebar.currentDocument = doc
            preview.baseURL = doc?.fileURL?.deletingLastPathComponent()
            preview.render(textView.string, line: 0, immediate: true)
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        let old = (textView.string as NSString).substring(with: range)
        highlighter.noteReplacement(old: old, new: replacementString ?? "")
        return true
    }

    func textDidChange(_ notification: Notification) {
        textView.invalidateLines()
        doc?.editorTextDidChange()
        if mode != .editor {
            preview.render(textView.string, line: mode == .split && Settings.syncScroll ? textView.topVisibleLine() : nil)
        }
        scheduleStatus()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        scheduleStatus()
    }

    private func scheduleStatus() {
        statusWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.updateStatusNow() }
        statusWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    private func updateStatusNow() {
        guard !statusBar.isHidden else { return }
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        let loc = min(sel.location, ns.length)
        let line = textView.lineNumber(at: loc)
        let col = loc - textView.lineStarts[line] + 1
        statusBar.update(text: textView.string, selection: ns.substring(with: NSRange(location: loc, length: min(sel.length, ns.length - loc))),
                         line: line + 1, column: col)
    }

    private func editorDidScroll() {
        guard mode == .split, Settings.syncScroll, Date() > suppressEditorSyncUntil else { return }
        preview.scrollTo(line: textView.topVisibleLine())
    }

    // MARK: - Modos

    func setMode(_ m: ViewMode, persist: Bool = true) {
        let previous = mode
        mode = m
        editorScroll.isHidden = (m == .reader)
        preview.isHidden = (m == .editor)
        placeDivider(centerIfSplit: true)
        // O split view só assenta o divisor depois do próximo layout; repete então.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.placeDivider(centerIfSplit: true)
            self.textView.fitWidthToClip()
            self.textView.updateInsets()
        }
        textView.typewriter = Settings.typewriter && m != .reader
        if m != .editor && (previous == .editor || !didInitialLayout) {
            preview.render(textView.string, line: textView.topVisibleLine(), immediate: true)
        }
        didInitialLayout = true
        if m == .reader {
            window?.makeFirstResponder(preview.webView)
        } else {
            window?.makeFirstResponder(textView)
        }
        modeGroup?.selectedIndex = m.rawValue
        if persist { Settings.viewMode = m }
        textView.fitWidthToClip()
        textView.updateInsets()
    }

    /// Posiciona o divisor editor|preview conforme o modo. Com um painel escondido, o NSSplitView
    /// deixava o divisor onde estava (uma linha cinza no meio do editor no modo "Só editor") até
    /// a janela ser redimensionada; empurrar para a borda resolve. No dividido, centraliza só
    /// quando pedido ou quando algum painel ficou inválido, respeitando a posição arrastada.
    private func placeDivider(centerIfSplit: Bool) {
        splitView.adjustSubviews()
        let w = splitView.bounds.width
        guard w > 0 else { return }
        switch mode {
        case .editor: splitView.setPosition(w, ofDividerAt: 0)
        case .reader: splitView.setPosition(0, ofDividerAt: 0)
        case .split:
            let editorW = editorScroll.frame.width
            if centerIfSplit || editorW < 240 || w - editorW < 240 {
                splitView.setPosition((w / 2).rounded(), ofDividerAt: 0)
            }
        }
        splitView.needsDisplay = true
    }

    @objc func showEditorOnly(_ sender: Any?) { exitFocusIfNeeded(); setMode(.editor) }
    @objc func showSplit(_ sender: Any?) { exitFocusIfNeeded(); setMode(.split) }
    @objc func showReader(_ sender: Any?) { exitFocusIfNeeded(); setMode(.reader) }

    @objc func modeGroupChanged(_ sender: NSToolbarItemGroup) {
        let idx = sender.selectedIndex
        exitFocusIfNeeded()
        setMode(ViewMode(rawValue: idx) ?? .split)
    }

    private func exitFocusIfNeeded() {
        if focusMode { toggleFocusMode(nil) }
    }

    @objc func toggleFocusMode(_ sender: Any?) {
        focusMode.toggle()
        if focusMode {
            modeBeforeFocus = mode
            window?.toolbar?.isVisible = false
            setMode(.editor, persist: false)
        } else {
            window?.toolbar?.isVisible = true
            setMode(modeBeforeFocus, persist: false)
        }
        applySettings()
        window?.makeFirstResponder(textView)
    }

    @objc func toggleSyncScroll(_ sender: Any?) {
        Settings.syncScroll.toggle()
    }

    @objc func toggleStatusBar(_ sender: Any?) {
        Settings.showStatusBar.toggle()
        updateStatusNow()
    }

    // MARK: - Exportar e imprimir

    private var baseName: String {
        let name = doc?.displayName ?? "Sem título"
        return (name as NSString).deletingPathExtension
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = baseName + ".html"
        panel.directoryURL = doc?.fileURL?.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            Exporter.exportHTML(markdown: self.textView.string, title: self.baseName,
                                appearance: window.effectiveAppearance, to: url) { err in
                if let err { self.showError(err) }
            }
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = baseName + ".pdf"
        panel.directoryURL = doc?.fileURL?.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            Exporter.exportPDF(markdown: self.textView.string, title: self.baseName,
                               baseURL: self.doc?.fileURL?.deletingLastPathComponent(),
                               appearance: window.effectiveAppearance, to: url) { err in
                if let err { self.showError(err) }
            }
        }
    }

    func printDocument() {
        guard let window else { return }
        Exporter.printDocument(markdown: textView.string, title: baseName,
                               baseURL: doc?.fileURL?.deletingLastPathComponent(),
                               appearance: window.effectiveAppearance, window: window)
    }

    private func showError(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    // MARK: - Validação de menus

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(showEditorOnly(_:)): item.state = mode == .editor && !focusMode ? .on : .off
        case #selector(showSplit(_:)): item.state = mode == .split && !focusMode ? .on : .off
        case #selector(showReader(_:)): item.state = mode == .reader && !focusMode ? .on : .off
        case #selector(toggleFocusMode(_:)): item.state = focusMode ? .on : .off
        case #selector(toggleSyncScroll(_:)): item.state = Settings.syncScroll ? .on : .off
        case #selector(toggleStatusBar(_:)): item.state = Settings.showStatusBar ? .on : .off
        case #selector(toggleDocumentSidebar(_:)): item.state = Settings.showSidebar && !focusMode ? .on : .off
        default: break
        }
        return true
    }

    // MARK: - Barra de ferramentas

    private func buildToolbar(in window: NSWindow) {
        let tb = NSToolbar(identifier: "MarcadoToolbar3")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = true
        tb.autosavesConfiguration = true
        window.toolbar = tb
        window.toolbarStyle = .unified
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebar, .mode, .space, .heading, .bold, .italic, .strike, .highlight, .code, .link, .quote, .bullet, .numbered, .task, .table,
         .flexibleSpace, .appearance, .focus, .export]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.image, .space, .flexibleSpace]
    }

    private func button(_ id: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ action: Selector, tip: String) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.paletteLabel = label
        item.toolTip = tip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.action = action
        item.target = nil
        item.isBordered = true
        return item
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .sidebar:
            return button(id, "Barra lateral", "sidebar.left", #selector(toggleDocumentSidebar(_:)), tip: "Documentos abertos e recentes (⌃⌘S)")
        case .mode:
            let images = ["square.and.pencil", "rectangle.split.2x1", "book"].map {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)!
            }
            let group = NSToolbarItemGroup(itemIdentifier: id, images: images, selectionMode: .selectOne,
                                           labels: ["Editor", "Dividido", "Leitura"],
                                           target: self, action: #selector(modeGroupChanged(_:)))
            group.label = "Modo"
            group.paletteLabel = "Modo de visualização"
            group.controlRepresentation = .expanded
            group.selectedIndex = mode.rawValue
            group.subitems.enumerated().forEach { i, sub in
                sub.toolTip = ["Só editor (⌘1)", "Editor e visualização (⌘2)", "Leitura (⌘3)"][i]
            }
            modeGroup = group
            return group
        case .bold: return button(id, "Negrito", "bold", #selector(MarkdownTextView.toggleBold(_:)), tip: "Negrito (⌘B)")
        case .italic: return button(id, "Itálico", "italic", #selector(MarkdownTextView.toggleItalic(_:)), tip: "Itálico (⌘I)")
        case .strike: return button(id, "Riscado", "strikethrough", #selector(MarkdownTextView.toggleStrikethrough(_:)), tip: "Riscado (⇧⌘X)")
        case .code: return button(id, "Código", "chevron.left.forwardslash.chevron.right", #selector(MarkdownTextView.toggleInlineCode(_:)), tip: "Código (⌘E)")
        case .link: return button(id, "Link", "link", #selector(MarkdownTextView.insertMarkdownLink(_:)), tip: "Link (⌘K)")
        case .image: return button(id, "Imagem", "photo", #selector(MarkdownTextView.insertMarkdownImage(_:)), tip: "Imagem (⇧⌘I)")
        case .quote: return button(id, "Citação", "text.quote", #selector(MarkdownTextView.toggleQuote(_:)), tip: "Citação (⇧⌘.)")
        case .bullet: return button(id, "Lista", "list.bullet", #selector(MarkdownTextView.toggleBulletList(_:)), tip: "Lista (⇧⌘L)")
        case .numbered: return button(id, "Numerada", "list.number", #selector(MarkdownTextView.toggleNumberedList(_:)), tip: "Lista numerada (⇧⌘O)")
        case .task: return button(id, "Tarefas", "checklist", #selector(MarkdownTextView.toggleTaskList(_:)), tip: "Lista de tarefas (⇧⌘C)")
        case .table: return button(id, "Tabela", "tablecells", #selector(MarkdownTextView.insertTable(_:)), tip: "Inserir tabela")
        case .focus: return button(id, "Foco", "arrow.up.left.and.arrow.down.right", #selector(toggleFocusMode(_:)), tip: "Modo foco (⇧⌘F). Esc sai")
        case .heading:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Título"
            item.paletteLabel = "Título"
            item.toolTip = "Títulos (⌥⌘1 a ⌥⌘6)"
            item.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Título")
            item.menu = AppDelegate.headingMenu()
            item.showsIndicator = true
            return item
        case .highlight:
            // Clique repete a última cor; a setinha abre as cores.
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Destacar"
            item.paletteLabel = "Destacar"
            item.toolTip = "Destacar texto (⇧⌘H repete a última cor)"
            item.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "Destacar")
            item.action = #selector(MarkdownTextView.highlightWithLastColor(_:))
            item.target = nil
            item.menu = AppDelegate.highlightMenu()
            item.showsIndicator = true
            return item
        case .appearance:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Aparência"
            item.paletteLabel = "Aparência"
            item.toolTip = "Tema, fonte e tamanho da leitura"
            item.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Aparência")
            item.menu = AppDelegate.appearanceMenu()
            item.showsIndicator = true
            return item
        case .export:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Exportar"
            item.paletteLabel = "Exportar"
            item.toolTip = "Exportar como HTML ou PDF"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Exportar")
            let menu = NSMenu()
            menu.addItem(withTitle: "Exportar como HTML…", action: #selector(exportHTML(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Exportar como PDF…", action: #selector(exportPDF(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Imprimir…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "")
            item.menu = menu
            item.showsIndicator = false
            return item
        default:
            return nil
        }
    }
}
