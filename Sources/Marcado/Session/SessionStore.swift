import AppKit

extension Notification.Name {
    /// Documentos abertos, alterados, fechados ou lista de recentes mudou.
    static let marcadoDocumentsChanged = Notification.Name("MarcadoDocumentsChanged")
}

/// Sessão no estilo do Sublime Text: ao abrir o app, volta o que estava aberto, inclusive
/// textos que nunca foram salvos (rascunhos). Os rascunhos são gravados em
/// ~/Library/Application Support/Marcado/Rascunhos a cada pausa na digitação, então resistem a
/// encerrar o app, desligar o Mac ou até a falta de energia.
enum SessionStore {
    static var isTerminating = false
    static var isRestoring = false
    /// Chave dos recentes em UserDefaults (o autoteste usa outra).
    static var recentsKey = ProcessInfo.processInfo.environment["MARCADO_SUPPORT_DIR"] == nil ? "recentFiles" : "recentFiles-teste"
    static let maxRecents = 50

    static let directory: URL = {
        let fm = FileManager.default
        let dir: URL
        if let custom = ProcessInfo.processInfo.environment["MARCADO_SUPPORT_DIR"] {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Marcado", isDirectory: true)
        }
        try? fm.createDirectory(at: dir.appendingPathComponent("Rascunhos"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: dir.appendingPathComponent("Descartados"), withIntermediateDirectories: true)
        return dir
    }()

    static var sessionURL: URL { directory.appendingPathComponent("sessao.json") }
    static func scratchURL(_ id: String) -> URL { directory.appendingPathComponent("Rascunhos/\(id).md") }

    struct Entry: Codable {
        var path: String?
        var scratch: String?
    }

    struct Session: Codable {
        var entries: [Entry]
        var active: Int?
        var savedAt: Date
    }

    // MARK: - Notificação

    private static var notifyPending = false

    static func notifyChanged() {
        guard !notifyPending else { return }
        notifyPending = true
        DispatchQueue.main.async {
            notifyPending = false
            NotificationCenter.default.post(name: .marcadoDocumentsChanged, object: nil)
        }
    }

    // MARK: - Recentes

    static var recentURLs: [URL] {
        (UserDefaults.standard.stringArray(forKey: recentsKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func noteRecent(_ url: URL) {
        guard url.isFileURL else { return }
        let p = url.standardizedFileURL.path
        if p.contains("/Autosave Information/") || p.hasPrefix(directory.path) { return }
        var list = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        list.removeAll { $0 == p }
        list.insert(p, at: 0)
        UserDefaults.standard.set(Array(list.prefix(maxRecents)), forKey: recentsKey)
        notifyChanged()
    }

    static func removeRecent(_ url: URL) {
        let p = url.standardizedFileURL.path
        var list = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        list.removeAll { $0 == p }
        UserDefaults.standard.set(list, forKey: recentsKey)
        notifyChanged()
    }

    static func clearRecents() {
        UserDefaults.standard.removeObject(forKey: recentsKey)
        notifyChanged()
    }

    // MARK: - Documentos abertos

    static func document(of window: NSWindow?) -> MarkdownDocument? {
        (window?.windowController as? DocumentWindowController)?.document as? MarkdownDocument
    }

    /// Documentos na ordem das abas.
    static func orderedDocuments() -> [MarkdownDocument] {
        let docs = NSDocumentController.shared.documents.compactMap { $0 as? MarkdownDocument }
        var result: [MarkdownDocument] = []
        var seen = Set<ObjectIdentifier>()
        func add(_ d: MarkdownDocument) {
            guard docs.contains(where: { $0 === d }), seen.insert(ObjectIdentifier(d)).inserted else { return }
            result.append(d)
        }
        for w in NSApp.windows where document(of: w) != nil {
            for tw in w.tabbedWindows ?? [w] {
                if let d = document(of: tw) { add(d) }
            }
        }
        docs.forEach(add)
        return result
    }

    /// Título de um rascunho: primeira linha com texto, como o Sublime faz nas abas sem nome.
    static func title(for text: String) -> String {
        var count = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            count += 1
            if count > 50 { break }
            let s = line.trimmingCharacters(in: CharacterSet(charactersIn: "#>-*+`=_ \t\r"))
            if !s.isEmpty { return s.count > 40 ? String(s.prefix(40)) + "…" : s }
        }
        return "Sem título"
    }

    // MARK: - Rascunhos

    static let debug = ProcessInfo.processInfo.environment["MARCADO_DEBUG"] != nil
    static func log(_ s: String) {
        guard debug else { return }
        FileHandle.standardError.write("[sessao] \(s)\n".data(using: .utf8)!)
    }

    static func writeScratch(for doc: MarkdownDocument) {
        guard doc.fileURL == nil else { return }
        let text = doc.currentText
        log("writeScratch id=\(doc.scratchID.prefix(8)) controller=\(doc.controller != nil) tv=\(doc.controller.map { ObjectIdentifier($0.textView).hashValue } ?? 0) texto=\(text.prefix(20).debugDescription)")
        let url = scratchURL(doc.scratchID)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    /// Apaga o rascunho (o texto foi salvo num arquivo de verdade).
    static func deleteScratch(_ id: String) {
        try? FileManager.default.removeItem(at: scratchURL(id))
    }

    /// Rascunho fechado sem salvar: vai para Descartados, onde fica 30 dias.
    static func discardScratch(_ id: String) {
        let fm = FileManager.default
        let src = scratchURL(id)
        guard fm.fileExists(atPath: src.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dst = directory.appendingPathComponent("Descartados/\(stamp)-\(id.prefix(8)).md")
        try? fm.moveItem(at: src, to: dst)
        pruneDiscarded()
    }

    private static func pruneDiscarded() {
        let fm = FileManager.default
        let dir = directory.appendingPathComponent("Descartados")
        let limit = Date().addingTimeInterval(-30 * 86400)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for f in files {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            if date < limit { try? fm.removeItem(at: f) }
        }
    }

    // MARK: - Gravar sessão

    private static var saveWork: DispatchWorkItem?

    static func scheduleSave() {
        if debug { log("scheduleSave docs=\(NSDocumentController.shared.documents.count)") }
        notifyChanged()
        guard !isRestoring, !isTerminating else { return }
        saveWork?.cancel()
        let w = DispatchWorkItem { saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    @discardableResult
    static func saveNow() -> Session? {
        guard !isRestoring, !isTerminating else { return nil }
        saveWork?.cancel()
        let key = NSApp.keyWindow ?? NSApp.mainWindow
        var entries: [Entry] = []
        var active: Int?
        for d in orderedDocuments() {
            if let url = d.fileURL {
                entries.append(Entry(path: url.path, scratch: nil))
            } else {
                writeScratch(for: d)
                guard FileManager.default.fileExists(atPath: scratchURL(d.scratchID).path) else { continue }
                entries.append(Entry(path: nil, scratch: d.scratchID))
            }
            if let w = d.windowControllers.first?.window, w === key { active = entries.count - 1 }
        }
        let session = Session(entries: entries, active: active, savedAt: Date())
        log("saveNow entries=\(entries.map { $0.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "rascunho:" + ($0.scratch ?? "").prefix(8) })")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(session) {
            try? data.write(to: sessionURL, options: .atomic)
        }
        // Rascunho que ficou sem documento (não deveria acontecer): guarda em Descartados.
        let keep = Set(entries.compactMap { $0.scratch })
        let open = Set(NSDocumentController.shared.documents.compactMap { ($0 as? MarkdownDocument)?.scratchID })
        if let files = try? FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Rascunhos"),
                                                                    includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "md" {
                let id = f.deletingPathExtension().lastPathComponent
                if !keep.contains(id) && !open.contains(id) { discardScratch(id) }
            }
        }
        return session
    }

    static func loadSession() -> Session? {
        guard let data = try? Data(contentsOf: sessionURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Session.self, from: data)
    }

    // MARK: - Encerramento

    /// Chamado antes de o AppKit revisar documentos não salvos ao encerrar ou desligar o Mac.
    /// Grava a sessão e libera os rascunhos (já estão em disco) para não aparecer o alerta de salvar.
    static func prepareForTermination() {
        guard !isTerminating else { return }
        saveNow()
        isTerminating = true
        let untitled = NSDocumentController.shared.documents.compactMap { $0 as? MarkdownDocument }.filter { $0.fileURL == nil }
        var cleared: [MarkdownDocument] = []
        for d in untitled {
            let safe = FileManager.default.fileExists(atPath: scratchURL(d.scratchID).path)
                || d.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if safe && d.isDocumentEdited {
                d.updateChangeCount(.changeCleared)
                cleared.append(d)
            }
        }
        // Se o encerramento for cancelado, o app continua vivo: volta ao normal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard isTerminating else { return }
            isTerminating = false
            for d in cleared where NSDocumentController.shared.documents.contains(where: { $0 === d }) {
                d.updateChangeCount(.changeDone)
            }
            scheduleSave()
        }
    }

    static func documentClosed() {
        log("documentClosed")
        scheduleSave()
        guard !isTerminating, NSApp.isRunning else { return }
        DispatchQueue.main.async {
            if !isTerminating && !isRestoring && NSDocumentController.shared.documents.isEmpty {
                WelcomeWindowController.show()
            }
        }
    }

    // MARK: - Restaurar

    static func restore(completion: @escaping () -> Void) {
        guard let session = loadSession(), !session.entries.isEmpty else {
            isRestoring = false
            completion()
            return
        }
        isRestoring = true
        let dc = NSDocumentController.shared
        var restored: [Int: MarkdownDocument] = [:]

        func step(_ i: Int) {
            guard i < session.entries.count else {
                isRestoring = false
                if let a = session.active, let d = restored[a] {
                    d.showWindows()
                }
                saveNow()
                notifyChanged()
                completion()
                return
            }
            let e = session.entries[i]
            if let path = e.path {
                guard FileManager.default.fileExists(atPath: path) else { step(i + 1); return }
                dc.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { doc, _, _ in
                    if let d = doc as? MarkdownDocument { restored[i] = d }
                    step(i + 1)
                }
            } else if let id = e.scratch,
                      let data = try? Data(contentsOf: scratchURL(id)),
                      let text = String(data: data, encoding: .utf8),
                      !text.isEmpty,
                      let d = try? dc.makeUntitledDocument(ofType: dc.defaultType ?? "net.daringfireball.markdown") as? MarkdownDocument {
                log("restore scratch \(id.prefix(8)) em doc novo \(d.scratchID.prefix(8))")
                d.scratchID = id
                d.loadedText = text
                d.refreshUntitledTitle()
                dc.addDocument(d)
                d.makeWindowControllers()
                d.showWindows()
                d.updateChangeCount(.changeDone)
                restored[i] = d
                DispatchQueue.main.async { step(i + 1) }
            } else {
                step(i + 1)
            }
        }
        step(0)
    }
}

/// Controlador de documentos do app: alimenta os recentes e prepara o encerramento.
final class MarcadoDocumentController: NSDocumentController {
    override func noteNewRecentDocumentURL(_ url: URL) {
        super.noteNewRecentDocumentURL(url)
        SessionStore.noteRecent(url)
    }

    override func clearRecentDocuments(_ sender: Any?) {
        super.clearRecentDocuments(sender)
        SessionStore.clearRecents()
    }

    override func reviewUnsavedDocuments(withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
                                         didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        SessionStore.prepareForTermination()
        super.reviewUnsavedDocuments(withAlertTitle: title, cancellable: cancellable, delegate: delegate,
                                     didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
    }
}
