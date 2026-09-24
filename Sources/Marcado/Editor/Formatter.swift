import AppKit

/// Ações de formatação Markdown. Todas alternam (aplicam ou removem) sobre a seleção
/// ou a linha atual e passam pelo shouldChangeText/didChangeText, então têm desfazer.
extension MarkdownTextView {

    // MARK: - Utilitários

    func replace(_ range: NSRange, with text: String, select sel: NSRange, action: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        let len = (string as NSString).length
        let loc = min(sel.location, len)
        setSelectedRange(NSRange(location: loc, length: min(sel.length, len - loc)))
        undoManager?.setActionName(action)
        scrollRangeToVisible(selectedRange())
    }

    func wordRange(at loc: Int) -> NSRange {
        let ns = string as NSString
        guard ns.length > 0 else { return NSRange(location: loc, length: 0) }
        let r = selectionRange(forProposedRange: NSRange(location: min(loc, ns.length), length: 0), granularity: .selectByWord)
        guard r.length > 0 else { return NSRange(location: loc, length: 0) }
        let word = ns.substring(with: r)
        if word.rangeOfCharacter(from: .alphanumerics) == nil { return NSRange(location: loc, length: 0) }
        return r
    }

    private func toggleWrap(_ mark: String, action: String) {
        let ns = string as NSString
        var sel = selectedRange()
        let m = (mark as NSString).length

        if sel.length >= 2 * m {
            let sub = ns.substring(with: sel)
            if sub.hasPrefix(mark) && sub.hasSuffix(mark) {
                let inner = (sub as NSString).substring(with: NSRange(location: m, length: sel.length - 2 * m))
                replace(sel, with: inner, select: NSRange(location: sel.location, length: (inner as NSString).length), action: action)
                return
            }
        }
        if sel.location >= m, NSMaxRange(sel) + m <= ns.length,
           ns.substring(with: NSRange(location: sel.location - m, length: m)) == mark,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: m)) == mark {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            let inner = ns.substring(with: sel)
            replace(outer, with: inner, select: NSRange(location: sel.location - m, length: sel.length), action: action)
            return
        }
        if sel.length == 0 { sel = wordRange(at: sel.location) }
        let inner = ns.substring(with: sel)
        replace(sel, with: mark + inner + mark,
                select: NSRange(location: sel.location + m, length: (inner as NSString).length), action: action)
    }

    private enum BlockKind: Equatable {
        case none, heading(Int), quote, bullet, numbered, task
    }

    private static let blockPrefix = try! NSRegularExpression(
        pattern: "^([ \\t]*)(#{1,6}[ \\t]+|>[ \\t]?|[-*+][ \\t]+\\[[ xX]\\][ \\t]+|[-*+][ \\t]+|\\d{1,9}[.)][ \\t]+)?")

    private func parseLine(_ line: String) -> (indent: String, kind: BlockKind, body: String) {
        let ns = line as NSString
        guard let m = Self.blockPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return ("", .none, line)
        }
        let indent = ns.substring(with: m.range(at: 1))
        let body = ns.substring(from: NSMaxRange(m.range))
        guard m.range(at: 2).location != NSNotFound else { return (indent, .none, body) }
        let p = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
        let kind: BlockKind
        if p.hasPrefix("#") { kind = .heading(p.prefix(while: { $0 == "#" }).count) }
        else if p.hasPrefix(">") { kind = .quote }
        else if p.contains("[") { kind = .task }
        else if p.first?.isNumber == true { kind = .numbered }
        else { kind = .bullet }
        return (indent, kind, body)
    }

    private func toggleBlock(_ kind: BlockKind, action: String) {
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)
        var text = ns.substring(with: lineRange)
        let trailingNewline = text.hasSuffix("\n")
        if trailingNewline { text.removeLast() }
        let lines = text.components(separatedBy: "\n")
        let parsed = lines.map(parseLine)
        let nonEmpty = parsed.enumerated().filter { !lines[$0.offset].trimmingCharacters(in: .whitespaces).isEmpty }
        let allHave = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.element.kind == kind }
        let single = lines.count == 1

        var n = 0
        let out: [String] = parsed.enumerated().map { i, p in
            if lines[i].trimmingCharacters(in: .whitespaces).isEmpty && !single { return lines[i] }
            if allHave || kind == .none { return p.indent + p.body }
            n += 1
            let prefix: String
            switch kind {
            case .heading(let lvl): prefix = String(repeating: "#", count: lvl) + " "
            case .quote: prefix = "> "
            case .bullet: prefix = "- "
            case .numbered: prefix = "\(n). "
            case .task: prefix = "- [ ] "
            case .none: prefix = ""
            }
            return p.indent + prefix + p.body
        }
        let newText = out.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let oldLen = (text as NSString).length + (trailingNewline ? 1 : 0)
        let newLen = (newText as NSString).length
        if sel.length == 0 && single {
            let caret = max(lineRange.location, sel.location + (newLen - oldLen))
            replace(lineRange, with: newText, select: NSRange(location: caret, length: 0), action: action)
        } else {
            replace(lineRange, with: newText,
                    select: NSRange(location: lineRange.location, length: newLen - (trailingNewline ? 1 : 0)), action: action)
        }
    }

    private func insertLinkLike(image: Bool) {
        let ns = string as NSString
        let sel = selectedRange()
        let text = ns.substring(with: sel)
        let bang = image ? "!" : ""
        let action = image ? "Inserir imagem" : "Inserir link"
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            let s = "\(bang)[](\(text))"
            replace(sel, with: s, select: NSRange(location: sel.location + (bang as NSString).length + 1, length: 0), action: action)
        } else if text.isEmpty {
            let label = image ? "descrição" : "texto"
            let s = "\(bang)[\(label)](https://)"
            replace(sel, with: s, select: NSRange(location: sel.location + (bang as NSString).length + 1,
                                                   length: (label as NSString).length), action: action)
        } else {
            let s = "\(bang)[\(text)](https://)"
            let urlLoc = sel.location + (bang as NSString).length + (text as NSString).length + 3
            replace(sel, with: s, select: NSRange(location: urlLoc, length: 8), action: action)
        }
    }

    // MARK: - Destaque colorido

    /// Última cor usada (⇧⌘H e o clique no botão da barra repetem essa).
    static var lastHighlight: HighlightColor = .amarelo

    /// Destaque que envolve `range` na linha: `==x==` ou `<mark class="c">x</mark>`.
    private func enclosingHighlight(_ range: NSRange) -> (outer: NSRange, inner: NSRange, color: HighlightColor)? {
        let ns = string as NSString
        let line = ns.lineRange(for: range)
        for (re, innerGroup) in [(SyntaxHighlighter.markEquals, 1), (SyntaxHighlighter.markTag, 2)] {
            for m in re.matches(in: string, range: line)
            where range.length > 0
                ? m.range.location <= range.location && NSMaxRange(range) <= NSMaxRange(m.range)
                : m.range.location < range.location && range.location < NSMaxRange(m.range) {
                var color = HighlightColor.amarelo
                if innerGroup == 2, m.range(at: 1).location != NSNotFound {
                    color = HighlightColor(name: ns.substring(with: m.range(at: 1))) ?? .amarelo
                }
                return (m.range, m.range(at: innerGroup), color)
            }
        }
        return nil
    }

    /// Tira todos os destaques de um trecho, deixando só o texto.
    static func stripHighlights(_ text: String) -> String {
        var out = text
        for (re, g) in [(SyntaxHighlighter.markTag, 2), (SyntaxHighlighter.markEquals, 1)] {
            out = re.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length),
                                              withTemplate: "$\(g)")
        }
        return out
    }

    /// Aplica a cor (ou remove, com `nil`). Dentro de um destaque existente: mesma cor remove,
    /// outra cor troca. Sem seleção vale a palavra do cursor; em várias linhas, cada linha
    /// é destacada à parte, preservando o marcador de lista, citação ou título.
    func applyHighlight(_ color: HighlightColor?) {
        let ns = string as NSString
        var sel = selectedRange()
        let action = color == nil ? "Remover destaque" : "Destacar"

        if let h = enclosingHighlight(sel) {
            let inner = ns.substring(with: h.inner)
            let text = (color == nil || color == h.color) ? inner : color!.wrap(inner)
            let offset = (text as NSString).range(of: inner).location
            replace(h.outer, with: text, select: NSRange(location: h.outer.location + offset, length: h.inner.length), action: action)
            return
        }

        if sel.length == 0 { sel = wordRange(at: sel.location) }
        let original = ns.substring(with: sel)
        let plain = Self.stripHighlights(original)
        guard let color else {
            if plain != original {
                replace(sel, with: plain, select: NSRange(location: sel.location, length: (plain as NSString).length), action: action)
            }
            return
        }
        if sel.length == 0 {
            // Sem palavra: deixa as marcas prontas com o cursor no meio.
            let empty = color.wrap("")
            let caret = color == .amarelo ? 2 : (empty as NSString).length - 7
            replace(sel, with: empty, select: NSRange(location: sel.location + caret, length: 0), action: action)
            return
        }
        let lines = plain.components(separatedBy: "\n")
        if lines.count == 1 {
            let inner = plain
            let lead = (color.wrap(inner) as NSString).range(of: inner).location
            replace(sel, with: color.wrap(inner),
                    select: NSRange(location: sel.location + lead, length: (inner as NSString).length), action: action)
            return
        }
        let out = lines.map { line -> String in
            let p = parseLine(line)
            let body = p.body.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return line }
            let prefix = String(line.dropLast(p.body.count))
            let trailing = String(p.body.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
            let leading = String(p.body.prefix(while: { $0 == " " || $0 == "\t" }))
            return prefix + leading + color.wrap(body) + trailing
        }.joined(separator: "\n")
        replace(sel, with: out, select: NSRange(location: sel.location, length: (out as NSString).length), action: action)
    }

    /// tag = HighlightColor.rawValue; -1 remove o destaque.
    @objc func highlightText(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag ?? 0
        guard tag >= 0, let c = HighlightColor(rawValue: tag) else { applyHighlight(nil); return }
        Self.lastHighlight = c
        applyHighlight(c)
    }

    @objc func highlightWithLastColor(_ sender: Any?) { applyHighlight(Self.lastHighlight) }

    @objc func removeHighlight(_ sender: Any?) { applyHighlight(nil) }

    // MARK: - Ações de menu e barra

    @objc func toggleBold(_ sender: Any?) { toggleWrap("**", action: "Negrito") }
    @objc func toggleItalic(_ sender: Any?) { toggleWrap("*", action: "Itálico") }
    @objc func toggleStrikethrough(_ sender: Any?) { toggleWrap("~~", action: "Riscado") }
    @objc func toggleInlineCode(_ sender: Any?) { toggleWrap("`", action: "Código") }
    @objc func insertMarkdownLink(_ sender: Any?) { insertLinkLike(image: false) }
    @objc func insertMarkdownImage(_ sender: Any?) { insertLinkLike(image: true) }

    /// tag 0 = texto normal, 1...6 = nível do título.
    @objc func setHeading(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag ?? 1
        toggleBlock(tag == 0 ? .none : .heading(tag), action: tag == 0 ? "Texto normal" : "Título \(tag)")
    }
    @objc func toggleQuote(_ sender: Any?) { toggleBlock(.quote, action: "Citação") }
    @objc func toggleBulletList(_ sender: Any?) { toggleBlock(.bullet, action: "Lista") }
    @objc func toggleNumberedList(_ sender: Any?) { toggleBlock(.numbered, action: "Lista numerada") }
    @objc func toggleTaskList(_ sender: Any?) { toggleBlock(.task, action: "Lista de tarefas") }

    @objc func insertCodeBlock(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        if sel.length == 0 {
            let line = ns.lineRange(for: sel)
            let raw = ns.substring(with: line)
            let endsNL = raw.hasSuffix("\n")
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let content = NSRange(location: line.location, length: line.length - (endsNL ? 1 : 0))
                replace(content, with: "```\n\n```", select: NSRange(location: line.location + 3, length: 0), action: "Bloco de código")
            } else {
                let at = NSMaxRange(line)
                let lead = endsNL ? "" : "\n"
                replace(NSRange(location: at, length: 0), with: lead + "```\n\n```\n",
                        select: NSRange(location: at + (lead as NSString).length + 3, length: 0), action: "Bloco de código")
            }
            return
        }
        let line = ns.lineRange(for: sel)
        var body = ns.substring(with: line)
        let nl = body.hasSuffix("\n")
        if nl { body.removeLast() }
        let s = "```\n" + body + "\n```" + (nl ? "\n" : "")
        replace(line, with: s, select: NSRange(location: line.location + 3, length: 0), action: "Bloco de código")
    }

    @objc func insertTable(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineText = ns.substring(with: line)
        let blank = lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let at = blank ? line.location : NSMaxRange(line)
        var s = ""
        if !blank { s += lineText.hasSuffix("\n") ? "\n" : "\n\n" }
        let header = "| Coluna 1 | Coluna 2 | Coluna 3 |\n| --- | --- | --- |\n|  |  |  |\n|  |  |  |\n"
        let headerStart = at + (s as NSString).length + 2
        s += header
        replace(NSRange(location: at, length: 0), with: s, select: NSRange(location: headerStart, length: 8), action: "Inserir tabela")
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineText = ns.substring(with: line)
        let blank = lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let at = blank ? line.location : NSMaxRange(line)
        var s = blank ? "" : (lineText.hasSuffix("\n") ? "\n" : "\n\n")
        s += "---\n\n"
        replace(NSRange(location: at, length: 0), with: s, select: NSRange(location: at + (s as NSString).length, length: 0), action: "Linha horizontal")
    }

    private static let formatActions: Set<Selector> = [
        #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleStrikethrough(_:)),
        #selector(toggleInlineCode(_:)), #selector(insertMarkdownLink(_:)),
        #selector(insertMarkdownImage(_:)), #selector(setHeading(_:)), #selector(toggleQuote(_:)),
        #selector(toggleBulletList(_:)), #selector(toggleNumberedList(_:)), #selector(toggleTaskList(_:)),
        #selector(insertCodeBlock(_:)), #selector(insertTable(_:)), #selector(insertHorizontalRule(_:)),
        #selector(insertFileLink(_:)), #selector(highlightText(_:)), #selector(highlightWithLastColor(_:)),
        #selector(removeHighlight(_:)), #selector(aiAsk(_:)), #selector(aiRun(_:)),
    ]

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, Self.formatActions.contains(action) {
            return isEditable && !isHiddenOrHasHiddenAncestor
        }
        return super.validateUserInterfaceItem(item)
    }
}
