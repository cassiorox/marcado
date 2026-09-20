import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var launching = true
    private var launchURLs: [URL] = []
    private var appearanceObservation: NSKeyValueObservation?

    // MARK: - Ciclo de vida

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Nada grava a sessão até ela ser restaurada.
        SessionStore.isRestoring = true
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SessionStore.restore { [weak self] in
            guard let self else { return }
            self.launching = false
            // Arquivo aberto pelo Finder junto com a abertura do app fica na frente.
            if !self.launchURLs.isEmpty {
                SidebarView.open(self.launchURLs)
            } else if NSDocumentController.shared.documents.isEmpty {
                WelcomeWindowController.show()
            }
        }
        // Tema Automático acompanha a troca claro/escuro do sistema.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Settings.didChange, object: nil)
            }
        }
    }

    /// O app abre na sessão anterior ou na tela de início, nunca num documento em branco.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// Clique no ícone do Dock (ou `open -a Marcado`). Devolvemos false para o AppKit não abrir
    /// um documento em branco, então cabe a nós garantir que alguma janela apareça: janela
    /// minimizada precisa de deminiaturize (makeKeyAndOrderFront não a traz de volta), janela
    /// que ficou fora da tela (monitor desconectado) precisa ser recentralizada, e o `flag`
    /// pode vir true por causa de um painel solto sem nenhuma janela de documento na tela.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if NSApp.isHidden { NSApp.unhide(nil) }
        let docs = SessionStore.orderedDocuments()
        let windows = docs.compactMap { $0.windowControllers.first?.window }
        if let w = windows.first(where: { $0.isVisible && !$0.isMiniaturized }) {
            Self.ensureOnScreen(w)
            if !flag || !windows.contains(where: { $0.isKeyWindow }) { w.makeKeyAndOrderFront(nil) }
        } else if let w = windows.first(where: { $0.isMiniaturized }) {
            w.deminiaturize(nil)
            w.makeKeyAndOrderFront(nil)
        } else if let d = docs.first {
            d.showWindows()
        } else {
            WelcomeWindowController.show()
        }
        NSApp.activate()
        return false
    }

    /// Janela cujo quadro não toca nenhuma tela (ex.: ficou num monitor que foi desconectado)
    /// volta para o centro da tela principal.
    static func ensureOnScreen(_ window: NSWindow) {
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        if !onScreen { window.center() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SessionStore.prepareForTermination()
        return .terminateNow
    }

    @objc func showWelcome(_ sender: Any?) {
        WelcomeWindowController.show()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if launching { launchURLs += urls }
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
    }

    // MARK: - Ações globais (aparência)

    @objc func setTheme(_ sender: NSMenuItem) {
        Settings.theme = ReaderTheme.allCases[sender.tag]
    }

    @objc func nextTheme(_ sender: Any?) {
        let all = ReaderTheme.allCases.filter { $0 != .automatico }
        let idx = all.firstIndex(of: Settings.theme) ?? -1
        Settings.theme = all[(idx + 1) % all.count]
    }

    @objc func setReaderFont(_ sender: NSMenuItem) {
        Settings.readerFont = ReaderFont.allCases[sender.tag]
    }

    @objc func setEditorFont(_ sender: NSMenuItem) {
        Settings.editorFont = EditorFont.allCases[sender.tag]
    }

    @objc func setReaderWidth(_ sender: NSMenuItem) {
        Settings.readerWidth = ReaderWidth.allCases[sender.tag]
    }

    @objc func setLineSpacing(_ sender: NSMenuItem) {
        Settings.lineSpacing = LineSpacing.allCases[sender.tag]
    }

    @objc func biggerText(_ sender: Any?) {
        Settings.readerSize += 1
        Settings.editorSize += 1
    }

    @objc func smallerText(_ sender: Any?) {
        Settings.readerSize -= 1
        Settings.editorSize -= 1
    }

    @objc func resetTextSize(_ sender: Any?) {
        Settings.readerSize = Settings.defaultReaderSize
        Settings.editorSize = Settings.defaultEditorSize
    }

    @objc func toggleTypewriter(_ sender: Any?) {
        Settings.typewriter.toggle()
    }

    @objc func toggleWrapCode(_ sender: Any?) {
        Settings.wrapCode.toggle()
    }

    @objc func makeDefaultForMarkdown(_ sender: Any?) {
        guard let type = UTType("net.daringfireball.markdown") else { return }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
            DispatchQueue.main.async {
                let alert = NSAlert()
                if let error {
                    alert.messageText = "Não foi possível definir o Marcado como padrão"
                    alert.informativeText = error.localizedDescription
                } else {
                    alert.messageText = "Pronto"
                    alert.informativeText = "Arquivos .md agora abrem no Marcado com duplo clique no Finder."
                }
                alert.runModal()
            }
        }
    }

    @objc func openMarkdownGuide(_ sender: Any?) {
        let guide = """
        # Guia rápido de Markdown

        ## Títulos
        # Título 1
        ## Título 2
        ### Título 3

        ## Ênfase
        **negrito**, *itálico*, ~~riscado~~ e `código`.

        ## Listas
        - item
        - outro item
          - item dentro

        1. primeiro
        2. segundo

        - [ ] tarefa pendente
        - [x] tarefa feita

        ## Links e imagens
        [texto do link](https://agencia4ads.com.br)

        ![descrição da imagem](imagem.png)

        ## Citação
        > Uma frase citada.

        ## Código
        ```
        bloco de código
        ```

        ## Tabela
        | Coluna 1 | Coluna 2 |
        | --- | --- |
        | a | b |

        ---

        Linha horizontal acima: três hífens.
        """
        let dc = NSDocumentController.shared
        guard let doc = try? dc.openUntitledDocumentAndDisplay(true) as? MarkdownDocument else { return }
        doc.controller?.replaceText(guide)
        doc.controller?.setMode(.split)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setTheme(_:)): item.state = ReaderTheme.allCases[item.tag] == Settings.theme ? .on : .off
        case #selector(setReaderFont(_:)): item.state = ReaderFont.allCases[item.tag] == Settings.readerFont ? .on : .off
        case #selector(setEditorFont(_:)): item.state = EditorFont.allCases[item.tag] == Settings.editorFont ? .on : .off
        case #selector(setReaderWidth(_:)): item.state = ReaderWidth.allCases[item.tag] == Settings.readerWidth ? .on : .off
        case #selector(setLineSpacing(_:)): item.state = LineSpacing.allCases[item.tag] == Settings.lineSpacing ? .on : .off
        case #selector(toggleTypewriter(_:)): item.state = Settings.typewriter ? .on : .off
        case #selector(toggleWrapCode(_:)): item.state = Settings.wrapCode ? .on : .off
        default: break
        }
        return true
    }

    // MARK: - Menus

    static func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        i.tag = tag
        return i
    }

    static func headingMenu() -> NSMenu {
        let m = NSMenu(title: "Título")
        m.addItem(item("Texto normal", #selector(MarkdownTextView.setHeading(_:)), "0", [.command, .option], tag: 0))
        for n in 1...6 {
            m.addItem(item("Título \(n)", #selector(MarkdownTextView.setHeading(_:)), "\(n)", [.command, .option], tag: n))
        }
        return m
    }

    static func appearanceMenu() -> NSMenu {
        let m = NSMenu(title: "Aparência")

        let themes = NSMenu(title: "Tema")
        for (i, t) in ReaderTheme.allCases.enumerated() {
            themes.addItem(item(t.title, #selector(setTheme(_:)), tag: i))
        }
        themes.addItem(.separator())
        themes.addItem(item("Próximo tema", #selector(nextTheme(_:)), "t", [.command, .control]))
        let themesItem = NSMenuItem(title: "Tema", action: nil, keyEquivalent: "")
        themesItem.submenu = themes
        m.addItem(themesItem)

        let fonts = NSMenu(title: "Fonte da leitura")
        for (i, f) in ReaderFont.allCases.enumerated() {
            let it = item(f.title, #selector(setReaderFont(_:)), tag: i)
            if let nf = NSFont(name: f.previewFontName, size: 13) { it.attributedTitle = NSAttributedString(string: f.title, attributes: [.font: nf]) }
            fonts.addItem(it)
        }
        let fontsItem = NSMenuItem(title: "Fonte da leitura", action: nil, keyEquivalent: "")
        fontsItem.submenu = fonts
        m.addItem(fontsItem)

        let efonts = NSMenu(title: "Fonte do editor")
        for (i, f) in EditorFont.allCases.enumerated() {
            efonts.addItem(item(f.title, #selector(setEditorFont(_:)), tag: i))
        }
        let efontsItem = NSMenuItem(title: "Fonte do editor", action: nil, keyEquivalent: "")
        efontsItem.submenu = efonts
        m.addItem(efontsItem)

        let widths = NSMenu(title: "Largura da leitura")
        for (i, w) in ReaderWidth.allCases.enumerated() {
            widths.addItem(item(w.title, #selector(setReaderWidth(_:)), tag: i))
        }
        let widthsItem = NSMenuItem(title: "Largura da leitura", action: nil, keyEquivalent: "")
        widthsItem.submenu = widths
        m.addItem(widthsItem)

        let spacing = NSMenu(title: "Entrelinha")
        for (i, s) in LineSpacing.allCases.enumerated() {
            spacing.addItem(item(s.title, #selector(setLineSpacing(_:)), tag: i))
        }
        let spacingItem = NSMenuItem(title: "Entrelinha", action: nil, keyEquivalent: "")
        spacingItem.submenu = spacing
        m.addItem(spacingItem)

        m.addItem(.separator())
        m.addItem(item("Aumentar texto", #selector(biggerText(_:)), "+"))
        let hiddenBigger = item("Aumentar texto", #selector(biggerText(_:)), "=")
        hiddenBigger.isHidden = true
        hiddenBigger.allowsKeyEquivalentWhenHidden = true
        m.addItem(hiddenBigger)
        m.addItem(item("Diminuir texto", #selector(smallerText(_:)), "-"))
        m.addItem(item("Tamanho padrão", #selector(resetTextSize(_:)), "0"))
        return m
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        i.submenu = menu
        return i
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        // Marcado
        let app = NSMenu(title: "Marcado")
        app.addItem(AppDelegate.item("Sobre o Marcado", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""))
        app.addItem(.separator())
        app.addItem(AppDelegate.item("Definir como app padrão para .md", #selector(makeDefaultForMarkdown(_:)), ""))
        app.addItem(.separator())
        let services = NSMenu(title: "Serviços")
        app.addItem(submenu("Serviços", services))
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(AppDelegate.item("Ocultar Marcado", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(AppDelegate.item("Ocultar outros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(AppDelegate.item("Mostrar tudo", #selector(NSApplication.unhideAllApplications(_:)), ""))
        app.addItem(.separator())
        app.addItem(AppDelegate.item("Encerrar Marcado", #selector(NSApplication.terminate(_:)), "q"))
        main.addItem(submenu("Marcado", app))

        // Arquivo
        let file = NSMenu(title: "Arquivo")
        file.addItem(AppDelegate.item("Abrir…", #selector(NSDocumentController.openDocument(_:)), "o"))
        let recent = NSMenu(title: "Abrir recente")
        recent.addItem(AppDelegate.item("Limpar menu", #selector(NSDocumentController.clearRecentDocuments(_:)), ""))
        file.addItem(submenu("Abrir recente", recent))
        file.addItem(AppDelegate.item("Novo", #selector(NSDocumentController.newDocument(_:)), "n"))
        file.addItem(.separator())
        file.addItem(AppDelegate.item("Fechar", #selector(NSWindow.performClose(_:)), "w"))
        file.addItem(AppDelegate.item("Salvar", #selector(NSDocument.save(_:)), "s"))
        // ⇧⌘S = Salvar como, como no Sublime Text (no padrão do Mac seria Duplicar).
        file.addItem(AppDelegate.item("Salvar como…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        file.addItem(AppDelegate.item("Duplicar", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift, .option]))
        file.addItem(AppDelegate.item("Renomear…", #selector(NSDocument.rename(_:)), ""))
        file.addItem(AppDelegate.item("Mover para…", #selector(NSDocument.move(_:)), ""))
        file.addItem(AppDelegate.item("Reverter para a versão salva", #selector(NSDocument.revertToSaved(_:)), ""))
        file.addItem(.separator())
        file.addItem(AppDelegate.item("Exportar como HTML…", #selector(DocumentWindowController.exportHTML(_:)), "e", [.command, .shift]))
        file.addItem(AppDelegate.item("Exportar como PDF…", #selector(DocumentWindowController.exportPDF(_:)), "e", [.command, .shift, .option]))
        file.addItem(.separator())
        file.addItem(AppDelegate.item("Imprimir…", #selector(NSDocument.printDocument(_:)), "p"))
        main.addItem(submenu("Arquivo", file))

        // Editar
        let edit = NSMenu(title: "Editar")
        edit.addItem(AppDelegate.item("Desfazer", Selector(("undo:")), "z"))
        edit.addItem(AppDelegate.item("Refazer", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(AppDelegate.item("Recortar", #selector(NSText.cut(_:)), "x"))
        edit.addItem(AppDelegate.item("Copiar", #selector(NSText.copy(_:)), "c"))
        edit.addItem(AppDelegate.item("Colar", #selector(NSText.paste(_:)), "v"))
        edit.addItem(AppDelegate.item("Colar como texto simples", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .shift, .option]))
        edit.addItem(AppDelegate.item("Apagar", #selector(NSText.delete(_:)), ""))
        edit.addItem(AppDelegate.item("Selecionar tudo", #selector(NSText.selectAll(_:)), "a"))
        edit.addItem(.separator())

        let find = NSMenu(title: "Localizar")
        let finderAction = #selector(NSResponder.performTextFinderAction(_:))
        find.addItem(AppDelegate.item("Localizar…", finderAction, "f", tag: NSTextFinder.Action.showFindInterface.rawValue))
        find.addItem(AppDelegate.item("Localizar e substituir…", finderAction, "f", [.command, .option], tag: NSTextFinder.Action.showReplaceInterface.rawValue))
        find.addItem(AppDelegate.item("Localizar seguinte", finderAction, "g", tag: NSTextFinder.Action.nextMatch.rawValue))
        find.addItem(AppDelegate.item("Localizar anterior", finderAction, "g", [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue))
        find.addItem(AppDelegate.item("Usar seleção para localizar", finderAction, "", tag: NSTextFinder.Action.setSearchString.rawValue))
        find.addItem(AppDelegate.item("Ir para a seleção", #selector(NSResponder.centerSelectionInVisibleArea(_:)), "j"))
        edit.addItem(submenu("Localizar", find))

        let spelling = NSMenu(title: "Ortografia e gramática")
        spelling.addItem(AppDelegate.item("Mostrar ortografia e gramática", #selector(NSText.showGuessPanel(_:)), ":"))
        spelling.addItem(AppDelegate.item("Verificar documento agora", #selector(NSText.checkSpelling(_:)), ";"))
        spelling.addItem(.separator())
        spelling.addItem(AppDelegate.item("Verificar ortografia ao digitar", #selector(NSTextView.toggleContinuousSpellChecking(_:)), ""))
        edit.addItem(submenu("Ortografia e gramática", spelling))
        edit.addItem(.separator())
        edit.addItem(AppDelegate.item("Emojis e símbolos", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", [.command, .control]))
        main.addItem(submenu("Editar", edit))

        // Formatar
        let format = NSMenu(title: "Formatar")
        format.addItem(AppDelegate.item("Negrito", #selector(MarkdownTextView.toggleBold(_:)), "b"))
        format.addItem(AppDelegate.item("Itálico", #selector(MarkdownTextView.toggleItalic(_:)), "i"))
        format.addItem(AppDelegate.item("Riscado", #selector(MarkdownTextView.toggleStrikethrough(_:)), "x", [.command, .shift]))
        format.addItem(AppDelegate.item("Código", #selector(MarkdownTextView.toggleInlineCode(_:)), "e"))
        format.addItem(.separator())
        format.addItem(submenu("Título", AppDelegate.headingMenu()))
        format.addItem(.separator())
        format.addItem(AppDelegate.item("Link…", #selector(MarkdownTextView.insertMarkdownLink(_:)), "k"))
        format.addItem(AppDelegate.item("Imagem…", #selector(MarkdownTextView.insertMarkdownImage(_:)), "i", [.command, .shift]))
        format.addItem(AppDelegate.item("Link para pasta ou arquivo…", #selector(MarkdownTextView.insertFileLink(_:)), "k", [.command, .option]))
        format.addItem(.separator())
        format.addItem(AppDelegate.item("Citação", #selector(MarkdownTextView.toggleQuote(_:)), ".", [.command, .shift]))
        format.addItem(AppDelegate.item("Lista", #selector(MarkdownTextView.toggleBulletList(_:)), "l", [.command, .shift]))
        format.addItem(AppDelegate.item("Lista numerada", #selector(MarkdownTextView.toggleNumberedList(_:)), "o", [.command, .shift]))
        format.addItem(AppDelegate.item("Lista de tarefas", #selector(MarkdownTextView.toggleTaskList(_:)), "c", [.command, .shift]))
        format.addItem(.separator())
        format.addItem(AppDelegate.item("Bloco de código", #selector(MarkdownTextView.insertCodeBlock(_:)), "k", [.command, .shift]))
        format.addItem(AppDelegate.item("Tabela", #selector(MarkdownTextView.insertTable(_:)), "t", [.command, .option]))
        format.addItem(AppDelegate.item("Linha horizontal", #selector(MarkdownTextView.insertHorizontalRule(_:)), "-", [.command, .option]))
        main.addItem(submenu("Formatar", format))

        // Visualizar
        let view = NSMenu(title: "Visualizar")
        view.addItem(AppDelegate.item("Só editor", #selector(DocumentWindowController.showEditorOnly(_:)), "1"))
        view.addItem(AppDelegate.item("Editor e visualização", #selector(DocumentWindowController.showSplit(_:)), "2"))
        view.addItem(AppDelegate.item("Leitura", #selector(DocumentWindowController.showReader(_:)), "3"))
        view.addItem(.separator())
        view.addItem(AppDelegate.item("Modo foco", #selector(DocumentWindowController.toggleFocusMode(_:)), "f", [.command, .shift]))
        view.addItem(AppDelegate.item("Máquina de escrever", #selector(toggleTypewriter(_:)), "t", [.command, .shift]))
        view.addItem(AppDelegate.item("Quebrar linhas nos blocos de código", #selector(toggleWrapCode(_:)), "l", [.command, .option]))
        view.addItem(AppDelegate.item("Rolagem sincronizada", #selector(DocumentWindowController.toggleSyncScroll(_:)), ""))
        view.addItem(AppDelegate.item("Barra de status", #selector(DocumentWindowController.toggleStatusBar(_:)), "/"))
        view.addItem(AppDelegate.item("Barra lateral", #selector(DocumentWindowController.toggleDocumentSidebar(_:)), "s", [.command, .control]))
        view.addItem(.separator())
        for it in AppDelegate.appearanceMenu().items {
            it.menu?.removeItem(it)
            view.addItem(it)
        }
        view.addItem(.separator())
        view.addItem(AppDelegate.item("Mostrar barra de ferramentas", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option, .shift]))
        view.addItem(AppDelegate.item("Personalizar barra de ferramentas…", #selector(NSWindow.runToolbarCustomizationPalette(_:)), ""))
        view.addItem(AppDelegate.item("Tela cheia", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        main.addItem(submenu("Visualizar", view))

        // Janela
        let window = NSMenu(title: "Janela")
        window.addItem(AppDelegate.item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(AppDelegate.item("Zoom", #selector(NSWindow.performZoom(_:)), ""))
        window.addItem(.separator())
        window.addItem(AppDelegate.item("Trazer todas para a frente", #selector(NSApplication.arrangeInFront(_:)), ""))
        window.addItem(.separator())
        window.addItem(AppDelegate.item("Início", #selector(showWelcome(_:)), "0", [.command, .shift]))
        main.addItem(submenu("Janela", window))
        NSApp.windowsMenu = window

        // Ajuda
        let help = NSMenu(title: "Ajuda")
        help.addItem(AppDelegate.item("Guia rápido de Markdown", #selector(openMarkdownGuide(_:)), ""))
        main.addItem(submenu("Ajuda", help))
        NSApp.helpMenu = help

        return main
    }
}

extension ReaderFont {
    /// Nome PostScript para mostrar o item de menu na própria fonte.
    var previewFontName: String {
        switch self {
        case .newYork: return "NewYork-Regular"
        case .georgia: return "Georgia"
        case .charter: return "Charter-Roman"
        case .palatino: return "Palatino-Roman"
        case .iowan: return "IowanOldStyle-Roman"
        case .sistema: return ".AppleSystemUIFont"
        case .avenir: return "AvenirNext-Regular"
        case .helvetica: return "HelveticaNeue"
        case .mono: return "SFMono-Regular"
        }
    }
}

extension AppDelegate {
    // MARK: - Linha de comando (autoteste e automação)

    /// Marcado --export-html entrada.md saida.html [--tema claro|sepia|escuro|meianoite]
    /// Marcado --export-pdf  entrada.md saida.pdf  [--tema ...]
    static func runCommandLine() {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        func fail(_ msg: String) -> Never {
            FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
            exit(1)
        }
        if let t = value(after: "--tema"), let theme = ReaderTheme(rawValue: t) {
            Settings.themeOverride = theme
        }
        let pdf = args.contains("--export-pdf")
        guard let i = args.firstIndex(of: pdf ? "--export-pdf" : "--export-html"), i + 2 < args.count else {
            fail("uso: Marcado --export-html|--export-pdf entrada.md saida [--tema nome]")
        }
        let input = URL(fileURLWithPath: args[i + 1])
        let output = URL(fileURLWithPath: args[i + 2])
        guard let text = try? String(contentsOf: input, encoding: .utf8) else { fail("não consegui ler \(input.path)") }
        let title = input.deletingPathExtension().lastPathComponent
        let appearance = NSAppearance(named: .aqua)!
        if pdf {
            Exporter.exportPDF(markdown: text, title: title, baseURL: input.deletingLastPathComponent(),
                               appearance: appearance, to: output) { err in
                if let err { fail("falha ao gerar PDF: \(err)") }
                print("OK: \(output.path)")
                exit(0)
            }
        } else {
            Exporter.exportHTML(markdown: text, title: title, appearance: appearance, to: output) { err in
                if let err { fail("falha: \(err)") }
                print("OK: \(output.path)")
                exit(0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { fail("tempo esgotado") }
    }
}
