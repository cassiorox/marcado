import AppKit
import UniformTypeIdentifiers

/// Colar e arrastar coisas que não são texto: imagem da área de transferência (vira PNG numa
/// pasta de anexos e `![](...)`), pastas e arquivos do Finder (viram link; clicar no preview abre
/// no Finder ou no app padrão) e caminho absoluto colado como texto.
extension MarkdownTextView {

    /// Pasta onde as imagens coladas são gravadas. A janela injeta: `anexos/` ao lado do documento
    /// salvo, ou Application Support/Marcado/Anexos para rascunhos.
    static var attachmentDirectoryProvider: ((MarkdownTextView) -> URL)?

    // MARK: - Colar e soltar

    override func paste(_ sender: Any?) {
        if insertFromPasteboard(NSPasteboard.general) { return }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            // Solta no ponto do mouse, como o NSTextView faria com texto.
            let p = convert(sender.draggingLocation, from: nil)
            let idx = characterIndexForInsertion(at: p)
            setSelectedRange(NSRange(location: idx, length: 0))
            if insertFromPasteboard(pb) { return true }
        }
        return super.performDragOperation(sender)
    }

    /// Devolve true se tratou o conteúdo (o texto comum segue o caminho normal).
    func insertFromPasteboard(_ pb: NSPasteboard) -> Bool {
        // 1. Arquivos e pastas do Finder.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let links = urls.map { Self.markdownLink(for: $0, relativeTo: documentFolder) }
            insertSnippet(links.joined(separator: "\n"), action: urls.count == 1 ? "Inserir link" : "Inserir links")
            return true
        }
        // 2. Texto: só intercepta se for um caminho absoluto existente (ex.: "Copiar como caminho").
        if let str = pb.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/"), !trimmed.contains("\n"),
               FileManager.default.fileExists(atPath: (trimmed as NSString).expandingTildeInPath) {
                insertSnippet(Self.markdownLink(for: URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath), relativeTo: documentFolder),
                              action: "Inserir link")
                return true
            }
            return false
        }
        // 3. Imagem (captura de tela, cópia de imagem num app).
        if let data = Self.pngData(from: pb) {
            guard let dir = Self.attachmentDirectoryProvider?(self) else { return false }
            do {
                let url = try Self.saveAttachment(data, in: dir)
                insertSnippet(Self.markdownImage(for: url, relativeTo: documentFolder), action: "Colar imagem")
            } catch {
                NSSound.beep()
                NSLog("Marcado: não gravou imagem colada: \(error)")
            }
            return true
        }
        return false
    }

    // MARK: - Ação de menu

    /// Formatar > Link para pasta ou arquivo…: escolhe no painel e insere o link.
    @objc func insertFileLink(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Link para pasta ou arquivo"
        panel.prompt = "Inserir link"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let self, !panel.urls.isEmpty else { return }
            let links = panel.urls.map { Self.markdownLink(for: $0, relativeTo: self.documentFolder) }
            self.insertSnippet(links.joined(separator: "\n"), action: "Inserir link")
        }
    }

    // MARK: - Utilitários

    /// Insere no cursor (substituindo a seleção) e deixa o cursor depois do trecho.
    func insertSnippet(_ text: String, action: String) {
        let sel = selectedRange()
        replace(sel, with: text, select: NSRange(location: sel.location + (text as NSString).length, length: 0), action: action)
    }

    /// `[Nome](</caminho/com espaços>)`. Pasta ou arquivo: o preview resolve como file:// e o
    /// clique abre no Finder (pasta) ou no app padrão (arquivo). Imagem vira `![]()`.
    static func markdownLink(for url: URL, relativeTo base: URL? = nil) -> String {
        if isImage(url) { return markdownImage(for: url, relativeTo: base) }
        return "[\(escapeLabel(displayName(url)))](\(destination(url, relativeTo: base)))"
    }

    static func markdownImage(for url: URL, relativeTo base: URL? = nil) -> String {
        "![\(escapeLabel(url.deletingPathExtension().lastPathComponent))](\(destination(url, relativeTo: base)))"
    }

    /// Pasta do documento salvo (para links relativos); nil em rascunho.
    static var documentFolderProvider: ((MarkdownTextView) -> URL?)?
    private var documentFolder: URL? { Self.documentFolderProvider?(self) }

    /// Caminho relativo à pasta do documento quando o arquivo está dentro dela; senão absoluto.
    /// Entre `<>` quando tem espaço ou parêntese, que é o que o CommonMark pede.
    static func destination(_ url: URL, relativeTo base: URL? = nil) -> String {
        var path = url.standardizedFileURL.path
        if let base = base?.standardizedFileURL.path, path.hasPrefix(base + "/") {
            path = String(path.dropFirst(base.count + 1))
        }
        let needsBrackets = path.contains(" ") || path.contains("(") || path.contains(")") || path.contains("<") || path.contains(">")
        return needsBrackets ? "<\(path)>" : path
    }

    static func displayName(_ url: URL) -> String {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    static func escapeLabel(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image)
    }

    /// PNG a partir da área de transferência: usa o PNG se houver, senão converte o TIFF/imagem.
    static func pngData(from pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png) { return png }
        guard pb.canReadObject(forClasses: [NSImage.self], options: nil),
              let image = (pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Grava `imagem-AAAAMMDD-HHMMSS.png` na pasta (criando-a), sem sobrescrever.
    static func saveAttachment(_ data: Data, in dir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: Date())
        var url = dir.appendingPathComponent("imagem-\(stamp).png")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("imagem-\(stamp)-\(n).png")
            n += 1
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}
