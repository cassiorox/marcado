import AppKit

extension NSColor {
    /// Cor a partir de "#rrggbb".
    convenience init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                  green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255,
                  alpha: 1)
    }
}

/// Cores do editor. Precisam bater com as variáveis de themes.css.
struct Palette {
    let bg: NSColor
    let text: NSColor
    let muted: NSColor
    let heading: NSColor
    let link: NSColor
    let codeText: NSColor
    let codeBg: NSColor
    let quote: NSColor
    let accent: NSColor
    let border: NSColor
    let selection: NSColor
}

enum ReaderTheme: String, CaseIterable {
    case automatico, claro, sepia, escuro, meianoite

    var title: String {
        switch self {
        case .automatico: return "Automático (segue o sistema)"
        case .claro: return "Claro"
        case .sepia: return "Sépia"
        case .escuro: return "Escuro"
        case .meianoite: return "Meia-noite"
        }
    }

    /// Resolve o Automático para Claro ou Escuro conforme a aparência.
    func resolved(for appearance: NSAppearance) -> ReaderTheme {
        guard self == .automatico else { return self }
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? .escuro : .claro
    }

    var isDark: Bool { self == .escuro || self == .meianoite }

    var palette: Palette {
        switch self {
        case .claro, .automatico:
            return Palette(bg: NSColor(hex: "#ffffff"), text: NSColor(hex: "#1d232b"), muted: NSColor(hex: "#8a929c"),
                           heading: NSColor(hex: "#0f1720"), link: NSColor(hex: "#003ec7"), codeText: NSColor(hex: "#b4235a"),
                           codeBg: NSColor(hex: "#f3f5f8"), quote: NSColor(hex: "#4a5563"), accent: NSColor(hex: "#003ec7"),
                           border: NSColor(hex: "#e3e7ec"), selection: NSColor(hex: "#cfdcff"))
        case .sepia:
            return Palette(bg: NSColor(hex: "#f6efdc"), text: NSColor(hex: "#3b3024"), muted: NSColor(hex: "#9a8a70"),
                           heading: NSColor(hex: "#2a2118"), link: NSColor(hex: "#8a4b12"), codeText: NSColor(hex: "#8f3b1b"),
                           codeBg: NSColor(hex: "#ece2c8"), quote: NSColor(hex: "#6a5a44"), accent: NSColor(hex: "#9a5b1c"),
                           border: NSColor(hex: "#ddd0b0"), selection: NSColor(hex: "#e8d49e"))
        case .escuro:
            return Palette(bg: NSColor(hex: "#1e2024"), text: NSColor(hex: "#d9dde3"), muted: NSColor(hex: "#7b828c"),
                           heading: NSColor(hex: "#f1f3f6"), link: NSColor(hex: "#7aa7ff"), codeText: NSColor(hex: "#f29bb8"),
                           codeBg: NSColor(hex: "#2a2d33"), quote: NSColor(hex: "#a8afb9"), accent: NSColor(hex: "#7aa7ff"),
                           border: NSColor(hex: "#363a41"), selection: NSColor(hex: "#34466b"))
        case .meianoite:
            return Palette(bg: NSColor(hex: "#0d1117"), text: NSColor(hex: "#c9d1d9"), muted: NSColor(hex: "#6e7681"),
                           heading: NSColor(hex: "#e6edf3"), link: NSColor(hex: "#58a6ff"), codeText: NSColor(hex: "#ff9bce"),
                           codeBg: NSColor(hex: "#161b22"), quote: NSColor(hex: "#9aa4ae"), accent: NSColor(hex: "#58a6ff"),
                           border: NSColor(hex: "#262c36"), selection: NSColor(hex: "#1f3a63"))
        }
    }
}

/// Fontes da visualização (CSS). Todas vêm com o macOS: nada é baixado.
enum ReaderFont: String, CaseIterable {
    case newYork, georgia, charter, palatino, iowan, sistema, avenir, helvetica, mono

    var title: String {
        switch self {
        case .newYork: return "New York"
        case .georgia: return "Georgia"
        case .charter: return "Charter"
        case .palatino: return "Palatino"
        case .iowan: return "Iowan Old Style"
        case .sistema: return "San Francisco (sistema)"
        case .avenir: return "Avenir Next"
        case .helvetica: return "Helvetica Neue"
        case .mono: return "SF Mono"
        }
    }

    var css: String {
        switch self {
        case .newYork: return "ui-serif, \"New York\", Georgia, serif"
        case .georgia: return "Georgia, serif"
        case .charter: return "Charter, \"Bitstream Charter\", Georgia, serif"
        case .palatino: return "Palatino, \"Palatino Linotype\", serif"
        case .iowan: return "\"Iowan Old Style\", Georgia, serif"
        case .sistema: return "-apple-system, BlinkMacSystemFont, \"Helvetica Neue\", sans-serif"
        case .avenir: return "\"Avenir Next\", Avenir, sans-serif"
        case .helvetica: return "\"Helvetica Neue\", Helvetica, Arial, sans-serif"
        case .mono: return "ui-monospace, \"SF Mono\", Menlo, monospace"
        }
    }

    var isSerif: Bool { [.newYork, .georgia, .charter, .palatino, .iowan].contains(self) }
}

/// Fontes do editor.
enum EditorFont: String, CaseIterable {
    case sfMono, menlo, sistema, newYork, georgia

    var title: String {
        switch self {
        case .sfMono: return "SF Mono"
        case .menlo: return "Menlo"
        case .sistema: return "San Francisco (sistema)"
        case .newYork: return "New York"
        case .georgia: return "Georgia"
        }
    }

    func font(size: CGFloat) -> NSFont {
        switch self {
        case .sfMono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .menlo:
            return NSFont(name: "Menlo", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .sistema:
            return NSFont.systemFont(ofSize: size)
        case .newYork:
            let base = NSFont.systemFont(ofSize: size)
            if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
            return NSFont(name: "Georgia", size: size) ?? base
        case .georgia:
            return NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size)
        }
    }
}

enum ReaderWidth: Int, CaseIterable {
    case estreita = 600, media = 720, larga = 920

    var title: String {
        switch self {
        case .estreita: return "Estreita"
        case .media: return "Média"
        case .larga: return "Larga"
        }
    }
}

enum LineSpacing: String, CaseIterable {
    case compacta, normal, ampla

    var title: String {
        switch self {
        case .compacta: return "Compacta"
        case .normal: return "Normal"
        case .ampla: return "Ampla"
        }
    }

    var css: Double {
        switch self {
        case .compacta: return 1.45
        case .normal: return 1.65
        case .ampla: return 1.9
        }
    }

    /// Espaço extra entre linhas no editor, como fração do tamanho da fonte.
    var editorFactor: CGFloat {
        switch self {
        case .compacta: return 0.2
        case .normal: return 0.4
        case .ampla: return 0.7
        }
    }
}

enum ViewMode: Int {
    case editor = 0, split = 1, reader = 2
}
