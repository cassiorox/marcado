import AppKit

private final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func urls(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { urls(sender).isEmpty ? [] : .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let u = urls(sender)
        onDrop?(u)
        return !u.isEmpty
    }
}

/// Tela de início: aparece quando não há documento aberto. O foco é abrir, não criar.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private static var instance: WelcomeWindowController?

    static func show() {
        let wc = instance ?? WelcomeWindowController()
        instance = wc
        wc.sidebar.reload()
        if wc.window?.isVisible != true { wc.window?.center() }
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func hide() {
        instance?.window?.orderOut(nil)
    }

    private let sidebar = SidebarView(frame: .zero)
    private let right = DropView()
    private let titleLabel = NSTextField(labelWithString: "Marcado")
    private let subtitle = NSTextField(labelWithString: "Abra um documento Markdown ou continue de onde parou.")
    private let hint = NSTextField(labelWithString: "Você também pode arrastar arquivos .md para esta janela.")
    private let openButton = NSButton(title: "Abrir documento…", target: nil, action: #selector(NSDocumentController.openDocument(_:)))
    private let newButton = NSButton(title: "Novo documento", target: nil, action: #selector(NSDocumentController.newDocument(_:)))
    private let divider = NSBox()
    private var observers: [NSObjectProtocol] = []

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Marcado"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 620, height: 400)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build(in: window)
        apply()
        observers.append(NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.apply()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .marcadoDocumentsChanged, object: nil, queue: .main) { [weak self] _ in
            if !NSDocumentController.shared.documents.isEmpty { self?.window?.orderOut(nil) }
        })
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(in window: NSWindow) {
        let content = NSView()
        window.contentView = content
        sidebar.topInset = 40
        right.onDrop = { SidebarView.open($0) }

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 88).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 88).isActive = true

        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        subtitle.font = .systemFont(ofSize: 14)
        hint.font = .systemFont(ofSize: 11)
        for l in [subtitle, hint] { l.alignment = .center; l.lineBreakMode = .byWordWrapping; l.maximumNumberOfLines = 2 }

        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.keyEquivalent = "\r"
        openButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        openButton.imagePosition = .imageLeading
        newButton.bezelStyle = .rounded
        newButton.controlSize = .large

        let buttons = NSStackView(views: [openButton, newButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [icon, titleLabel, subtitle, buttons, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(18, after: icon)
        stack.setCustomSpacing(24, after: subtitle)
        stack.setCustomSpacing(18, after: buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false

        divider.boxType = .custom
        divider.borderWidth = 0

        for v in [sidebar, divider, right] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        right.addSubview(stack)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 300),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: content.topAnchor),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            right.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            right.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            right.topAnchor.constraint(equalTo: content.topAnchor),
            right.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: right.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: right.centerYAnchor, constant: -10),
            stack.widthAnchor.constraint(lessThanOrEqualTo: right.widthAnchor, constant: -48),
        ])
    }

    private func apply() {
        guard let window else { return }
        let chosen = Settings.theme
        window.appearance = chosen == .automatico ? nil : NSAppearance(named: chosen.isDark ? .darkAqua : .aqua)
        let theme = chosen.resolved(for: window.effectiveAppearance)
        let p = theme.palette
        window.backgroundColor = p.bg
        right.wantsLayer = true
        right.layer?.backgroundColor = p.bg.cgColor
        divider.fillColor = p.border
        titleLabel.textColor = p.heading
        subtitle.textColor = p.muted
        hint.textColor = p.muted
        sidebar.apply(p, dark: theme.isDark)
    }
}
