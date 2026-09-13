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

    override func printDocument(_ sender: Any?) {
        controller?.printDocument()
    }
}
