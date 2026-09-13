import AppKit

/// Realce de sintaxe Markdown feito à mão sobre o NSTextStorage (TextKit 1).
/// A cada edição realça só o parágrafo alterado; blocos de código cercados (```)
/// são recalculados no documento todo porque mudam o sentido de muitas linhas.
final class SyntaxHighlighter: NSObject, NSTextStorageDelegate {
    private(set) var palette: Palette = ReaderTheme.claro.palette
    private(set) var baseFont: NSFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private var monoFont: NSFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private var paragraph = NSParagraphStyle()
    private var forceFull = true

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: palette.text, .paragraphStyle: paragraph]
    }

    func configure(palette: Palette, font: NSFont, spacing: LineSpacing) {
        self.palette = palette
        self.baseFont = font
        self.monoFont = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.94, weight: .regular)
        let p = NSMutableParagraphStyle()
        p.lineSpacing = font.pointSize * spacing.editorFactor
        self.paragraph = p
        forceFull = true
    }

    /// Chamado pelo delegate do text view antes de cada troca de texto.
    func noteReplacement(old: String, new: String) {
        if old.contains("```") || old.contains("~~~") || new.contains("```") || new.contains("~~~")
            || new.utf16.count > 400 || old.utf16.count > 400 {
            forceFull = true
        }
    }

    func highlightAll(_ ts: NSTextStorage) {
        ts.beginEditing()
        highlight(ts, range: NSRange(location: 0, length: ts.length), fences: fenceRanges(in: ts.string as NSString))
        ts.endEditing()
        forceFull = false
    }

    func textStorage(_ ts: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let ns = ts.string as NSString
        let fences = fenceRanges(in: ns)
        if forceFull {
            forceFull = false
            highlight(ts, range: NSRange(location: 0, length: ns.length), fences: fences)
            return
        }
        var r = ns.paragraphRange(for: NSRange(location: min(editedRange.location, ns.length),
                                               length: min(editedRange.length, ns.length - min(editedRange.location, ns.length))))
        for f in fences where NSIntersectionRange(f, r).length > 0 || NSLocationInRange(r.location, f) {
            r = NSUnionRange(r, f)
        }
        highlight(ts, range: r, fences: fences)
    }

    // MARK: - Regras

    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
    }

    private static let heading = rx("^(#{1,6})[ \\t]+.*$")
    private static let quote = rx("^[ \\t]*>.*$")
    private static let quoteMark = rx("^[ \\t]*(>+)")
    private static let list = rx("^[ \\t]*([-*+]|\\d{1,9}[.)])[ \\t]+")
    private static let task = rx("^[ \\t]*[-*+][ \\t]+(\\[[ xX]\\])")
    private static let hr = rx("^[ \\t]*([-*_])([ \\t]*\\1){2,}[ \\t]*$")
    private static let bold = rx("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italicStar = rx("(?<![\\*\\w\\\\])\\*(?=[^\\s*])(.+?)(?<=[^\\s*])\\*(?![\\*\\w])")
    private static let italicUnderscore = rx("(?<![_\\w\\\\])_(?=[^\\s_])(.+?)(?<=[^\\s_])_(?![_\\w])")
    private static let strike = rx("~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let inlineCode = rx("(`+)(?!`)(.+?)(?<!`)\\1(?!`)")
    private static let link = rx("(!?\\[)([^\\]\\n]*)(\\]\\()([^)\\n]*)(\\))")
    private static let url = rx("(?<![(<\\w])https?://[^\\s<>)\\]]+")
    private static let htmlComment = rx("<!--.*?-->")

    private func fenceRanges(in ns: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var openStart: Int? = nil
        var openMark = ""
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, lineRange, enclosing, _ in
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespaces)
            if let start = openStart {
                if line.hasPrefix(openMark) && line.trimmingCharacters(in: CharacterSet(charactersIn: "`~")).isEmpty {
                    result.append(NSRange(location: start, length: NSMaxRange(enclosing) - start))
                    openStart = nil
                }
            } else if line.hasPrefix("```") || line.hasPrefix("~~~") {
                openStart = lineRange.location
                openMark = String(line.prefix(3))
            }
        }
        if let start = openStart {
            result.append(NSRange(location: start, length: ns.length - start))
        }
        return result
    }

    private func highlight(_ ts: NSTextStorage, range: NSRange, fences: [NSRange]) {
        guard range.length > 0 else { return }
        let ns = ts.string as NSString
        ts.setAttributes(baseAttributes, range: range)

        func inFence(_ r: NSRange) -> Bool {
            fences.contains { NSLocationInRange(r.location, $0) }
        }
        func each(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            re.enumerateMatches(in: ts.string, options: [], range: range) { m, _, _ in
                if let m, !inFence(m.range) { body(m) }
            }
        }
        func color(_ r: NSRange, _ c: NSColor) {
            if r.location != NSNotFound && r.length > 0 { ts.addAttribute(.foregroundColor, value: c, range: r) }
        }
        func trait(_ r: NSRange, _ t: NSFontTraitMask) {
            ts.enumerateAttribute(.font, in: r, options: []) { v, sub, _ in
                guard let f = v as? NSFont else { return }
                ts.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: t), range: sub)
            }
        }
        func muteDelimiters(_ m: NSTextCheckingResult, _ len: Int) {
            color(NSRange(location: m.range.location, length: len), palette.muted)
            color(NSRange(location: NSMaxRange(m.range) - len, length: len), palette.muted)
        }

        each(Self.heading) { m in
            let level = m.range(at: 1).length
            let scale: CGFloat = [1.45, 1.28, 1.14, 1.06, 1.0, 1.0][level - 1]
            let f = NSFontManager.shared.convert(baseFont.withSize(baseFont.pointSize * scale), toHaveTrait: .boldFontMask)
            ts.addAttribute(.font, value: f, range: m.range)
            color(m.range, palette.heading)
            color(m.range(at: 1), palette.muted)
        }
        each(Self.quote) { m in
            color(m.range, palette.quote)
            trait(m.range, .italicFontMask)
        }
        each(Self.quoteMark) { m in color(m.range(at: 1), palette.accent) }
        each(Self.list) { m in color(m.range(at: 1), palette.accent) }
        each(Self.task) { m in color(m.range(at: 1), palette.accent) }
        each(Self.hr) { m in color(m.range, palette.muted) }
        each(Self.bold) { m in
            trait(m.range, .boldFontMask)
            color(m.range(at: 2), palette.heading)
            muteDelimiters(m, 2)
        }
        each(Self.italicStar) { m in trait(m.range, .italicFontMask); muteDelimiters(m, 1) }
        each(Self.italicUnderscore) { m in trait(m.range, .italicFontMask); muteDelimiters(m, 1) }
        each(Self.strike) { m in
            ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            color(m.range, palette.muted)
        }
        each(Self.link) { m in
            color(m.range, palette.muted)
            color(m.range(at: 2), palette.link)
        }
        each(Self.url) { m in color(m.range, palette.link) }
        each(Self.htmlComment) { m in color(m.range, palette.muted) }
        each(Self.inlineCode) { m in
            ts.addAttributes([.font: monoFont, .foregroundColor: palette.codeText, .backgroundColor: palette.codeBg], range: m.range)
            ts.removeAttribute(.strikethroughStyle, range: m.range)
            let n = m.range(at: 1).length
            color(NSRange(location: m.range.location, length: n), palette.muted)
            color(NSRange(location: NSMaxRange(m.range) - n, length: n), palette.muted)
        }

        for f in fences {
            let r = NSIntersectionRange(f, range)
            guard r.length > 0 else { continue }
            ts.addAttributes([.font: monoFont, .foregroundColor: palette.text, .backgroundColor: palette.codeBg], range: r)
            ts.removeAttribute(.strikethroughStyle, range: r)
            // Linhas das cercas em cinza.
            let first = ns.lineRange(for: NSRange(location: f.location, length: 0))
            color(NSIntersectionRange(first, range), palette.muted)
            let lastLoc = max(f.location, NSMaxRange(f) - 1)
            let last = ns.lineRange(for: NSRange(location: lastLoc, length: 0))
            let lastText = ns.substring(with: last).trimmingCharacters(in: .whitespacesAndNewlines)
            if last.location != first.location && (lastText.hasPrefix("```") || lastText.hasPrefix("~~~")) {
                color(NSIntersectionRange(last, range), palette.muted)
            }
        }
    }
}
