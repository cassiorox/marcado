import AppKit

/// Documento Markdown: texto puro UTF-8, sem formato próprio.
/// Sem arquivo (rascunho), o texto vive em SessionStore e o nome da aba é a primeira linha.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var loadedText = ""
    var scratchID = UUID().uuidString
    private(set) var untitledTitle = "Sem título"
    private var scratchWork: DispatchWorkItem?

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        SessionStore.log("makeWindowControllers id=\(scratchID.prefix(8)) url=\(fileURL?.lastPathComponent ?? "-") texto=\(loadedText.prefix(15).debugDescription)")
        let wc = DocumentWindowController(text: loadedText, isNew: fileURL == nil)
        addWindowController(wc)
        // Rascunho que já nasce com texto (Duplicar, restauração): nome da aba e cópia em disco.
        if fileURL == nil && !loadedText.isEmpty {
            refreshUntitledTitle()
            SessionStore.writeScratch(for: self)
        }
        SessionStore.scheduleSave()
    }

    var controller: DocumentWindowController? { windowControllers.first as? DocumentWindowController }

    var currentText: String { controller?.textView.string ?? loadedText }

    override var displayName: String! {
        get { fileURL == nil ? untitledTitle : super.displayName }
        set { super.displayName = newValue }
    }

    func refreshUntitledTitle() {
        let t = SessionStore.title(for: currentText)
        guard t != untitledTitle else { return }
        untitledTitle = t
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
        SessionStore.notifyChanged()
    }

    /// Chamado pelo editor a cada alteração do texto.
    func editorTextDidChange() {
        guard fileURL == nil else { return }
        scratchWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.fileURL == nil else { return }
            self.refreshUntitledTitle()
            SessionStore.writeScratch(for: self)
            SessionStore.scheduleSave()
        }
        scratchWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(currentText.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        var text: String? = String(data: data, encoding: .utf8)
        if text == nil { text = String(data: data, encoding: .windowsCP1252) }
        if text == nil { text = String(data: data, encoding: .isoLatin1) }
        guard let text else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        loadedText = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        controller?.replaceText(loadedText)  // Reverter
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        typeName == "public.plain-text" ? "txt" : "md"
    }

    override var shouldRunSavePanelWithAccessoryView: Bool { false }

    override var fileURL: URL? {
        didSet {
            controller?.documentURLChanged()
            if fileURL != nil && oldValue == nil {
                scratchWork?.cancel()
                SessionStore.deleteScratch(scratchID)
            }
            SessionStore.scheduleSave()
        }
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        SessionStore.notifyChanged()
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        SessionStore.notifyChanged()
    }

    override func close() {
        let url = fileURL
        scratchWork?.cancel()
        if url == nil && !SessionStore.isTerminating {
            // Fechado de propósito sem salvar: o rascunho vai para Descartados.
            SessionStore.discardScratch(scratchID)
        }
        super.close()
        if let url { SessionStore.noteRecent(url) }
        SessionStore.documentClosed()
    }

    // MARK: - Duplicar como arquivo

    /// Arquivo salvo: Duplicar cria "Nome cópia.md" na mesma pasta, abre e já pede o nome novo.
    /// Rascunho segue o Duplicar padrão (outro rascunho).
    override func duplicate(_ sender: Any?) {
        guard let url = fileURL else { super.duplicate(sender); return }
        Self.duplicateFile(url, text: currentText)
    }

    /// Nome livre ao lado do original, no padrão do Finder: "Nome cópia.md", "Nome cópia 2.md"...
    static func copyURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 1
        while true {
            let name = base + (n == 1 ? " cópia" : " cópia \(n)")
            let candidate = dir.appendingPathComponent(ext.isEmpty ? name : name + "." + ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// Grava a cópia (com o texto que está na tela, se o original estiver aberto), abre numa aba
    /// nova e abre o campo de renomear do título. Se o nome não for trocado, fica "cópia".
    @discardableResult
    static func duplicateFile(_ url: URL, text: String? = nil, rename: Bool = true) -> URL? {
        let dest = copyURL(for: url)
        do {
            if let text {
                try Data(text.utf8).write(to: dest, options: .withoutOverwriting)
            } else {
                try FileManager.default.copyItem(at: url, to: dest)
            }
        } catch {
            NSApp.presentError(error)
            return nil
        }
        NSDocumentController.shared.openDocument(withContentsOf: dest, display: true) { doc, _, error in
            if let error { NSApp.presentError(error); return }
            guard rename, let doc else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { doc.rename(nil) }
        }
        return dest
    }

    override func printDocument(_ sender: Any?) {
        controller?.printDocument()
    }
}
