import AppKit

/// Painel da IA, aberto como folha sobre a janela do documento. Mostra o pedido (editável),
/// a resposta chegando aos poucos (também editável) e os botões para aplicar na nota.
final class AIPanelController: NSObject, NSWindowDelegate {
    private static var open: [AIPanelController] = []

    private weak var textView: MarkdownTextView?
    private let action: AIAction?
    private let range: NSRange
    private let isSelection: Bool
    private let note: String

    let window: NSWindow
    private let promptField = NSTextField()
    let resultView = NSTextView()
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private var generateButton: NSButton!
    private var stopButton: NSButton!
    private var replaceButton: NSButton!
    private var insertButton: NSButton!
    private var copyButton: NSButton!
    private var task: Task<Void, Never>?

    init(textView: MarkdownTextView, action: AIAction?, range: NSRange, isSelection: Bool, note: String) {
        self.textView = textView
        self.action = action
        self.range = range
        self.isSelection = isSelection
        self.note = note
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        super.init()
        window.minSize = NSSize(width: 520, height: 380)
        window.delegate = self
        build()
    }

    func present(on parent: NSWindow) {
        Self.open.append(self)
        parent.beginSheet(window) { [weak self] _ in
            guard let self else { return }
            self.task?.cancel()
            Self.open.removeAll { $0 === self }
        }
        if action != nil {
            generate(nil)
        } else {
            window.makeFirstResponder(promptField)
        }
    }

    // MARK: - Montagem

    private func button(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        return b
    }

    private func build() {
        let scopeText = isSelection ? "trecho selecionado" : "nota inteira"
        let config = AIConfig.load()
        let heading = NSTextField(labelWithString: (action?.title ?? "Perguntar à IA") + "  ·  " + scopeText)
        heading.font = .boldSystemFont(ofSize: 14)
        let modelLabel = NSTextField(labelWithString: config.isReady ? config.activeModel : "sem chave configurada")
        modelLabel.font = .systemFont(ofSize: 11)
        modelLabel.textColor = .secondaryLabelColor
        let top = NSStackView(views: [heading, NSView(), modelLabel])
        top.orientation = .horizontal

        promptField.placeholderString = isSelection
            ? "O que fazer com o trecho? Ex.: transforme em e-mail formal, crie 3 títulos, explique…"
            : "O que você precisa? Ex.: resuma em 5 tópicos, liste as pendências, crie um prompt a partir disso…"
        promptField.stringValue = action?.instruction ?? ""
        promptField.usesSingleLineMode = false
        promptField.lineBreakMode = .byWordWrapping
        promptField.cell?.wraps = true
        promptField.cell?.isScrollable = false
        promptField.target = self
        promptField.action = #selector(generate(_:))
        promptField.font = .systemFont(ofSize: 13)
        promptField.heightAnchor.constraint(equalToConstant: 52).isActive = true

        generateButton = button("Gerar", #selector(generate(_:)))
        stopButton = button("Parar", #selector(stop(_:)))
        stopButton.isHidden = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail
        let promptRow = NSStackView(views: [spinner, status, NSView(), stopButton, generateButton])
        promptRow.orientation = .horizontal

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = resultView
        resultView.isRichText = false
        resultView.allowsUndo = true
        resultView.font = .systemFont(ofSize: 13.5)
        resultView.textContainerInset = NSSize(width: 8, height: 8)
        resultView.isAutomaticQuoteSubstitutionEnabled = false
        resultView.isAutomaticDashSubstitutionEnabled = false
        resultView.autoresizingMask = [.width]
        resultView.isVerticallyResizable = true
        resultView.textContainer?.widthTracksTextView = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let close = button("Fechar", #selector(closePanel(_:)))
        close.keyEquivalent = "\u{1b}"
        copyButton = button("Copiar", #selector(copyResult(_:)))
        insertButton = button("Inserir abaixo", #selector(insertBelow(_:)))
        replaceButton = button(isSelection ? "Substituir seleção" : "Substituir nota", #selector(replaceTarget(_:)))
        let primary = action?.insertsBelow == true || action == nil ? insertButton! : replaceButton!
        primary.keyEquivalent = "\r"
        primary.keyEquivalentModifierMask = [.command]
        let bottom = NSStackView(views: [close, NSView(), copyButton, insertButton, replaceButton])
        bottom.orientation = .horizontal

        let stack = NSStackView(views: [top, promptField, promptRow, scroll, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [top, promptField, promptRow, scroll, bottom] as [NSView] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true
        }
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        updateButtons(running: false)
        if !config.isReady {
            status.stringValue = "Configure a chave em Marcado > Ajustes (⌘,)."
        } else if action == nil {
            status.stringValue = "Enter gera. ⌘Enter insere o resultado na nota."
        }
    }

    private func updateButtons(running: Bool) {
        let has = !resultView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        generateButton.isHidden = running
        generateButton.title = has ? "Gerar de novo" : "Gerar"
        stopButton.isHidden = !running
        for b in [replaceButton, insertButton, copyButton] { b?.isEnabled = has && !running }
        running ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    // MARK: - Geração

    private func buildPrompt(_ request: String) -> String {
        let target = (note as NSString).substring(with: range)
        if action == nil {
            var s = ""
            if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s += "<nota>\n\(note)\n</nota>\n\n"
            }
            if isSelection {
                s += "<trecho_selecionado>\n\(target)\n</trecho_selecionado>\n\n"
                s += "Pedido sobre o trecho selecionado (use a nota como contexto): \(request)"
            } else {
                s += "Pedido: \(request)"
            }
            return s
        }
        return "<texto>\n\(target)\n</texto>\n\nPedido: \(request)"
    }

    @objc private func generate(_ sender: Any?) {
        let request = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { NSSound.beep(); return }
        let config = AIConfig.load()
        guard config.isReady else {
            status.stringValue = "Nenhuma chave configurada. Abra Marcado > Ajustes (⌘,)."
            NSSound.beep()
            return
        }
        task?.cancel()
        resultView.string = ""
        status.stringValue = "Gerando com \(config.activeModel)…"
        updateButtons(running: true)
        let prompt = buildPrompt(request)
        task = Task { @MainActor [weak self] in
            do {
                for try await chunk in AIClient.stream(config: config, system: MarkdownTextView.aiSystemPrompt, prompt: prompt) {
                    guard let self else { return }
                    self.resultView.textStorage?.append(NSAttributedString(string: chunk, attributes: [
                        .font: self.resultView.font ?? NSFont.systemFont(ofSize: 13.5),
                        .foregroundColor: NSColor.textColor,
                    ]))
                    self.resultView.scrollToEndOfDocument(nil)
                }
                guard let self else { return }
                if Task.isCancelled {
                    self.status.stringValue = "Interrompido."
                } else {
                    self.status.stringValue = "Pronto. Revise e escolha como aplicar."
                    self.resultView.string = Self.stripFences(self.resultView.string)
                }
            } catch {
                self?.status.stringValue = ""
                if let self {
                    let alert = NSAlert()
                    alert.messageText = "Não foi possível gerar"
                    alert.informativeText = error.localizedDescription
                    alert.beginSheetModal(for: self.window, completionHandler: nil)
                }
            }
            self?.updateButtons(running: false)
        }
    }

    /// Tira a cerca ``` que alguns modelos põem em volta da resposta inteira.
    static func stripFences(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```"), t.hasSuffix("```"), t.count > 6 else { return t }
        var lines = t.components(separatedBy: "\n")
        guard lines.count >= 2 else { return t }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n")
    }

    @objc private func stop(_ sender: Any?) {
        task?.cancel()
        status.stringValue = "Interrompido."
        updateButtons(running: false)
    }

    // MARK: - Aplicar

    private var result: String { resultView.string.trimmingCharacters(in: .whitespacesAndNewlines) }

    @objc private func replaceTarget(_ sender: Any?) {
        guard let tv = textView, !result.isEmpty else { return }
        let r = result
        tv.replace(range, with: r, select: NSRange(location: range.location, length: (r as NSString).length), action: "IA")
        closePanel(nil)
    }

    @objc private func insertBelow(_ sender: Any?) {
        guard let tv = textView, !result.isEmpty else { return }
        let ns = tv.string as NSString
        let at = min(NSMaxRange(range), ns.length)
        let before = at > 0 ? ns.substring(with: NSRange(location: at - 1, length: 1)) : ""
        let lead = at == 0 ? "" : (before == "\n" ? "\n" : "\n\n")
        let text = lead + result + "\n"
        tv.replace(NSRange(location: at, length: 0), with: text,
                   select: NSRange(location: at + (lead as NSString).length, length: (result as NSString).length), action: "IA")
        closePanel(nil)
    }

    @objc private func copyResult(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        status.stringValue = "Copiado."
    }

    @objc private func closePanel(_ sender: Any?) {
        task?.cancel()
        window.sheetParent?.endSheet(window)
    }
}
