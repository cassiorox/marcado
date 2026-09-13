import AppKit

/// Preferências globais (valem para todas as janelas), persistidas em UserDefaults.
/// Toda alteração publica `Settings.didChange` e cada janela se reaplica.
enum Settings {
    static let didChange = Notification.Name("MarcadoSettingsDidChange")
    fileprivate static let d = UserDefaults.standard

    static let defaultReaderSize = 19
    static let defaultEditorSize = 15

    private static func changed() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Usado só pela linha de comando (--tema), não é persistido.
    static var themeOverride: ReaderTheme?

    static var theme: ReaderTheme {
        get { if let o = themeOverride { return o }; return ReaderTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .automatico }
        set { d.set(newValue.rawValue, forKey: "theme"); changed() }
    }

    static var readerFont: ReaderFont {
        get { ReaderFont(rawValue: d.string(forKey: "readerFont") ?? "") ?? .newYork }
        set { d.set(newValue.rawValue, forKey: "readerFont"); changed() }
    }

    static var readerSize: Int {
        get { let v = d.integer(forKey: "readerSize"); return v == 0 ? defaultReaderSize : min(34, max(13, v)) }
        set { d.set(min(34, max(13, newValue)), forKey: "readerSize"); changed() }
    }

    static var readerWidth: ReaderWidth {
        get { ReaderWidth(rawValue: d.integer(forKey: "readerWidth")) ?? .media }
        set { d.set(newValue.rawValue, forKey: "readerWidth"); changed() }
    }

    static var lineSpacing: LineSpacing {
        get { LineSpacing(rawValue: d.string(forKey: "lineSpacing") ?? "") ?? .normal }
        set { d.set(newValue.rawValue, forKey: "lineSpacing"); changed() }
    }

    static var editorFont: EditorFont {
        get { EditorFont(rawValue: d.string(forKey: "editorFont") ?? "") ?? .sfMono }
        set { d.set(newValue.rawValue, forKey: "editorFont"); changed() }
    }

    static var editorSize: Int {
        get { let v = d.integer(forKey: "editorSize"); return v == 0 ? defaultEditorSize : min(30, max(10, v)) }
        set { d.set(min(30, max(10, newValue)), forKey: "editorSize"); changed() }
    }

    /// Modo da última janela usada; vira o padrão da próxima.
    static var viewMode: ViewMode {
        get { ViewMode(rawValue: d.object(forKey: "viewMode") as? Int ?? 1) ?? .split }
        set { d.set(newValue.rawValue, forKey: "viewMode") }
    }

    static var typewriter: Bool {
        get { d.bool(forKey: "typewriter") }
        set { d.set(newValue, forKey: "typewriter"); changed() }
    }

    static var showStatusBar: Bool {
        get { d.object(forKey: "showStatusBar") as? Bool ?? true }
        set { d.set(newValue, forKey: "showStatusBar"); changed() }
    }

    static var syncScroll: Bool {
        get { d.object(forKey: "syncScroll") as? Bool ?? true }
        set { d.set(newValue, forKey: "syncScroll"); changed() }
    }

    static var showSidebar: Bool {
        get { d.object(forKey: "showSidebar") as? Bool ?? true }
        set { d.set(newValue, forKey: "showSidebar"); changed() }
    }

    /// Largura da barra lateral. Não publica mudança: cada janela aplica ao virar a janela ativa.
    static var sidebarWidth: CGFloat {
        get { let v = d.double(forKey: "sidebarWidth"); return v == 0 ? 270 : min(480, max(180, CGFloat(v))) }
        set { d.set(Double(newValue), forKey: "sidebarWidth") }
    }

    static var collapsedSidebarSections: Set<String> {
        get { Set(d.stringArray(forKey: "collapsedSidebarSections") ?? []) }
        set { d.set(Array(newValue), forKey: "collapsedSidebarSections") }
    }

    /// Objeto enviado ao preview (window.marcado.apply).
    static func previewSettings(appearance: NSAppearance) -> [String: Any] {
        [
            "theme": theme.resolved(for: appearance).rawValue,
            "font": readerFont.css,
            "size": readerSize,
            "width": readerWidth.rawValue,
            "lh": lineSpacing.css,
        ]
    }
}

/// Localiza a pasta web (preview.html, CSS, markdown-it). No .app fica em
/// Contents/Resources/web; rodando via `swift run`, usa a pasta do projeto.
enum AppResources {
    static var webDirectory: URL {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: r.appendingPathComponent("preview.html").path) {
            return r
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Marcado
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // raiz
            .appendingPathComponent("Resources/web")
    }

    static var previewURL: URL { webDirectory.appendingPathComponent("preview.html") }

    static var themesCSS: String {
        (try? String(contentsOf: webDirectory.appendingPathComponent("themes.css"), encoding: .utf8)) ?? ""
    }
}
