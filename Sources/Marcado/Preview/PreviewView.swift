import AppKit
import WebKit

/// Evita ciclo de retenção entre WKUserContentController e o handler.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

/// Visualização renderizada (WKWebView + preview.html + markdown-it).
final class PreviewView: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private var loaded = false
    private var pending: (text: String, line: Double?)?
    private var renderWork: DispatchWorkItem?
    private var lastText: String?

    var baseURL: URL?
    /// Linha do editor correspondente ao topo do preview, quando o usuário rola o preview.
    var onUserScroll: ((Double) -> Void)?

    override init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let ucc = WKUserContentController()
        config.userContentController = ucc
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frame)
        ucc.add(WeakScriptHandler(self), name: "marcado")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        wantsLayer = true
        webView.loadFileURL(AppResources.previewURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    required init?(coder: NSCoder) { fatalError() }

    func setBackground(_ color: NSColor) {
        layer?.backgroundColor = color.cgColor
        webView.underPageBackgroundColor = color
    }

    /// Agenda uma renderização. `immediate` pula o atraso (troca de modo, abertura).
    func render(_ text: String, line: Double?, immediate: Bool = false) {
        renderWork?.cancel()
        guard loaded else { pending = (text, line); return }
        let work = DispatchWorkItem { [weak self] in self?.doRender(text, line: line) }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.12), execute: work)
    }

    private func doRender(_ text: String, line: Double?) {
        lastText = text
        var args: [String: Any] = ["text": text, "base": baseURL?.absoluteString ?? ""]
        args["line"] = line ?? -1
        webView.callAsyncJavaScript("marcado.render(text, base || null, line)", arguments: args, in: nil, in: .page, completionHandler: nil)
    }

    func apply(settings: [String: Any]) {
        guard loaded else { return }
        webView.callAsyncJavaScript("marcado.apply(s)", arguments: ["s": settings], in: nil, in: .page, completionHandler: nil)
    }

    func scrollTo(line: Double) {
        guard loaded else { return }
        webView.callAsyncJavaScript("marcado.scrollToLine(l)", arguments: ["l": line], in: nil, in: .page, completionHandler: nil)
    }

    var onLoad: (() -> Void)?

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        onLoad?()
        if let p = pending {
            pending = nil
            doRender(p.text, line: p.line)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        Self.openLink(url)
    }

    static func openLink(_ url: URL) {
        if url.isFileURL {
            let ext = url.pathExtension.lowercased()
            if ["md", "markdown", "mdown", "mkd", "txt"].contains(ext) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                return
            }
            if url.fragment != nil && url.path == AppResources.previewURL.path { return }
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "scroll":
            if let line = body["line"] as? Double { onUserScroll?(line) }
            else if let line = body["line"] as? Int { onUserScroll?(Double(line)) }
        case "copy":
            if let text = body["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        default:
            break
        }
    }
}
