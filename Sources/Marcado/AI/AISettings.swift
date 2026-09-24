import AppKit

/// Marcado > Ajustes (⌘,): provedor de IA, chaves e modelos da Claude e da OpenRouter.
final class AISettingsWindowController: NSWindowController {
    static let shared = AISettingsWindowController()

    private let providerPopup = NSPopUpButton()
    private let claudeKey = NSSecureTextField()
    private let claudeModel = NSTextField()
    private let openRouterKey = NSSecureTextField()
    private let openRouterModel = NSTextField()
    private let status = NSTextField(labelWithString: "")
    private var testTask: Task<Void, Never>?

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Ajustes de IA"
        super.init(window: w)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        load()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        return l
    }

    private func note(_ s: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func build() {
        providerPopup.addItems(withTitles: AIProvider.allCases.map(\.title))
        claudeKey.placeholderString = "sk-ant-…"
        claudeModel.placeholderString = AIConfig.defaultClaudeModel
        openRouterKey.placeholderString = "sk-or-…"
        openRouterModel.placeholderString = AIConfig.defaultOpenRouterModel
        for f in [claudeKey, claudeModel, openRouterKey, openRouterModel] as [NSTextField] {
            f.widthAnchor.constraint(equalToConstant: 340).isActive = true
        }

        let grid = NSGridView(views: [
            [label("Usar:"), providerPopup],
            [NSGridCell.emptyContentView, NSView()],
            [label("Chave da Claude:"), claudeKey],
            [label("Modelo da Claude:"), claudeModel],
            [NSGridCell.emptyContentView, note("Crie a chave em console.anthropic.com > API Keys.")],
            [label("Chave da OpenRouter:"), openRouterKey],
            [label("Modelo da OpenRouter:"), openRouterModel],
            [NSGridCell.emptyContentView, note("Crie a chave em openrouter.ai/keys. Modelo no formato provedor/modelo, como aparece no site.")],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.row(at: 1).height = 4
        grid.column(at: 0).xPlacement = .trailing

        let privacy = note("As chaves ficam só neste Mac, em ~/Library/Application Support/Marcado/ia.json, legíveis só pelo seu usuário. O texto só sai do Mac quando você usa uma ação do menu IA.")
        privacy.preferredMaxLayoutWidth = 500

        let test = NSButton(title: "Testar conexão", target: self, action: #selector(testConnection(_:)))
        let save = NSButton(title: "Salvar", target: self, action: #selector(saveAndClose(_:)))
        save.keyEquivalent = "\r"
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let buttons = NSStackView(views: [status, NSView(), test, save])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [grid, privacy, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window?.contentView = content
    }

    private func load() {
        let c = AIConfig.load()
        providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: c.provider) ?? 0)
        claudeKey.stringValue = c.claudeKey
        claudeModel.stringValue = c.claudeModel
        openRouterKey.stringValue = c.openRouterKey
        openRouterModel.stringValue = c.openRouterModel
        status.stringValue = ""
    }

    private var current: AIConfig {
        var c = AIConfig()
        c.provider = AIProvider.allCases[max(0, providerPopup.indexOfSelectedItem)]
        c.claudeKey = claudeKey.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        c.claudeModel = claudeModel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        c.openRouterKey = openRouterKey.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        c.openRouterModel = openRouterModel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return c
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try current.save()
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    @objc private func saveAndClose(_ sender: Any?) {
        if persist() { window?.close() }
    }

    @objc private func testConnection(_ sender: Any?) {
        guard persist() else { return }
        let c = current
        status.stringValue = "Testando \(c.activeModel)…"
        testTask?.cancel()
        let win = window
        testTask = Task { @MainActor [weak self] in
            var reply = ""
            do {
                for try await chunk in AIClient.stream(config: c, system: "Responda só com a palavra ok.", prompt: "Teste de conexão.") {
                    reply += chunk
                }
                self?.status.stringValue = "Funcionou (\(c.activeModel)): \(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
            } catch {
                self?.status.stringValue = ""
                let a = NSAlert()
                a.messageText = "A conexão falhou"
                a.informativeText = error.localizedDescription
                if let win { a.beginSheetModal(for: win, completionHandler: nil) }
            }
        }
    }
}
