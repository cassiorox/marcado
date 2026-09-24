import AppKit

/// Editor de texto puro. Largura de leitura limitada (texto centralizado em janelas largas),
/// modo máquina de escrever (linha do cursor sempre no meio) e Esc para sair do modo foco.
final class MarkdownTextView: NSTextView {
    var maxLineWidth: CGFloat = 780 { didSet { updateInsets() } }
    var typewriter = false { didSet { updateInsets(); if typewriter { centerCaret() } } }
    var onEscape: (() -> Bool)?

    static func make() -> (NSScrollView, MarkdownTextView) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero

        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.smartInsertDeleteEnabled = false
        tv.textContainerInset = NSSize(width: 32, height: 28)
        scroll.documentView = tv
        // A largura do editor precisa seguir o painel mesmo quando o layout muda com a janela
        // em segundo plano (aba não visível, troca de modo): sem isso o texto fica com a largura
        // antiga, é cortado na borda e a barra de rolagem aparece solta no meio da janela.
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(tv, selector: #selector(clipFrameChanged(_:)),
                                               name: NSView.frameDidChangeNotification, object: scroll.contentView)
        return (scroll, tv)
    }

    @objc private func clipFrameChanged(_ note: Notification) { fitWidthToClip() }

    /// Ajusta a largura do editor à área visível e zera o deslocamento horizontal.
    func fitWidthToClip() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let w = clip.bounds.width
        if w > 0, abs(frame.width - w) > 0.5 {
            // Só a largura: a altura o NSTextView acerta sozinho quando o layout termina.
            // Chamar sizeToFit aqui, no meio do layout, deixava trechos sem redesenhar.
            setFrameSize(NSSize(width: w, height: frame.height))
            needsDisplay = true
        }
        if clip.bounds.origin.x != 0 {
            clip.setBoundsOrigin(NSPoint(x: 0, y: clip.bounds.origin.y))
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    func updateInsets() {
        let width = bounds.width
        let horizontal = max(28, (width - maxLineWidth) / 2)
        var vertical: CGFloat = 28
        if typewriter, let clip = enclosingScrollView?.contentView {
            vertical = max(28, clip.bounds.height / 2 - 20)
        }
        let inset = NSSize(width: horizontal.rounded(), height: vertical.rounded())
        if inset != textContainerInset {
            textContainerInset = inset
        }
    }

    // MARK: - Menu do botão direito

    /// Coloca "Destacar" no topo do menu de contexto, como no Notion.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard isEditable else { return menu }
        let item = NSMenuItem(title: "Destacar", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
        item.submenu = AppDelegate.highlightMenu()
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    // MARK: - Máquina de escrever

    func centerCaret() {
        guard typewriter, let lm = layoutManager, let tc = textContainer,
              let clip = enclosingScrollView?.contentView else { return }
        let len = (string as NSString).length
        let loc = selectedRange().location
        lm.ensureLayout(for: tc)
        var rect: NSRect
        if loc >= len, lm.extraLineFragmentTextContainer != nil {
            rect = lm.extraLineFragmentRect
        } else if len == 0 {
            rect = .zero
        } else {
            let g = lm.glyphIndexForCharacter(at: min(loc, len - 1))
            rect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        }
        let y = rect.midY + textContainerOrigin.y - clip.bounds.height / 2
        let maxY = max(0, frame.height - clip.bounds.height)
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: min(maxY, max(0, y))))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    override func didChangeText() {
        super.didChangeText()
        if typewriter {
            DispatchQueue.main.async { [weak self] in self?.centerCaret() }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onEscape, onEscape() { return }  // Esc
        super.keyDown(with: event)
        if typewriter, [123, 124, 125, 126, 115, 119, 116, 121].contains(event.keyCode) {
            centerCaret()
        }
    }

    // MARK: - Linhas (para rolagem sincronizada)

    private var cachedLineStarts: [Int]? = nil

    func invalidateLines() { cachedLineStarts = nil }

    var lineStarts: [Int] {
        if let c = cachedLineStarts { return c }
        var starts = [0]
        let ns = string as NSString
        let len = ns.length
        var i = 0
        let buf = UnsafeMutablePointer<unichar>.allocate(capacity: max(len, 1))
        defer { buf.deallocate() }
        ns.getCharacters(buf, range: NSRange(location: 0, length: len))
        while i < len {
            if buf[i] == 10 { starts.append(i + 1) }
            i += 1
        }
        cachedLineStarts = starts
        return starts
    }

    /// Número da linha (0-based) que contém o caractere.
    func lineNumber(at charIndex: Int) -> Int {
        let s = lineStarts
        var lo = 0, hi = s.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if s[mid] <= charIndex { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Linha fracionária no topo da área visível.
    func topVisibleLine() -> Double {
        guard let lm = layoutManager, let tc = textContainer, let clip = enclosingScrollView?.contentView else { return 0 }
        let top = clip.bounds.minY
        if top <= 1 { return 0 }
        if clip.bounds.maxY >= frame.height - 1 { return Double(lineStarts.count) }
        let y = top - textContainerOrigin.y + 4
        let glyph = lm.glyphIndex(for: NSPoint(x: 0, y: max(0, y)), in: tc)
        let charIdx = lm.characterIndexForGlyph(at: glyph)
        let ns = string as NSString
        guard ns.length > 0 else { return 0 }
        let line = lineNumber(at: min(charIdx, ns.length - 1))
        let para = ns.paragraphRange(for: NSRange(location: lineStarts[line], length: 0))
        let gr = lm.glyphRange(forCharacterRange: para, actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: gr, in: tc)
        let frac = rect.height > 0 ? max(0, min(1, (y - rect.minY) / rect.height)) : 0
        return Double(line) + Double(frac)
    }

    /// Rola para deixar a linha fracionária no topo.
    func scrollTo(line: Double) {
        guard let lm = layoutManager, let tc = textContainer, let clip = enclosingScrollView?.contentView else { return }
        let starts = lineStarts
        let ns = string as NSString
        var y: CGFloat
        if line <= 0 || ns.length == 0 {
            y = 0
        } else if Int(line) >= starts.count {
            y = frame.height
        } else {
            let l = Int(line)
            let para = ns.paragraphRange(for: NSRange(location: min(starts[l], ns.length), length: 0))
            let gr = lm.glyphRange(forCharacterRange: para, actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: gr, in: tc)
            y = rect.minY + CGFloat(line - Double(l)) * rect.height + textContainerOrigin.y - 4
        }
        let maxY = max(0, frame.height - clip.bounds.height)
        clip.setBoundsOrigin(NSPoint(x: 0, y: min(maxY, max(0, y))))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }
}
