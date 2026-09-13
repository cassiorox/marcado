import AppKit

/// Rodapé com contagem de palavras, caracteres, tempo de leitura e posição do cursor.
final class StatusBarView: NSView {
    static let height: CGFloat = 26

    private let left = NSTextField(labelWithString: "")
    private let right = NSTextField(labelWithString: "")
    private let line = NSBox()
    private var bg = NSColor.windowBackgroundColor

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for l in [left, right] {
            l.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            l.lineBreakMode = .byTruncatingTail
            l.translatesAutoresizingMaskIntoConstraints = false
            addSubview(l)
        }
        line.boxType = .custom
        line.borderWidth = 0
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        right.alignment = .right
        left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            left.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            right.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
            right.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ p: Palette) {
        layer?.backgroundColor = p.bg.cgColor
        line.fillColor = p.border
        left.textColor = p.muted
        right.textColor = p.muted
    }

    static func countWords(_ s: String) -> Int {
        var n = 0
        s.enumerateSubstrings(in: s.startIndex..<s.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
        return n
    }

    static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "pt_BR")
        return "\(f.string(from: NSNumber(value: n)) ?? String(n)) \(n == 1 ? one : many)"
    }

    func update(text: String, selection: String, line: Int, column: Int) {
        let words = Self.countWords(text)
        let chars = text.count
        let minutes = Int((Double(words) / 200).rounded(.up))
        var parts: [String] = []
        if !selection.isEmpty {
            parts.append("\(Self.countWords(selection)) de \(Self.plural(words, "palavra", "palavras"))")
        } else {
            parts.append(Self.plural(words, "palavra", "palavras"))
        }
        parts.append(Self.plural(chars, "caractere", "caracteres"))
        parts.append(words == 0 ? "0 min de leitura" : (minutes <= 1 ? "1 min de leitura" : "\(minutes) min de leitura"))
        left.stringValue = parts.joined(separator: "   ·   ")
        right.stringValue = "Linha \(line), coluna \(column)"
    }
}
