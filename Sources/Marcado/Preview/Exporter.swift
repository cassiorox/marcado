import AppKit
import WebKit
import PDFKit

/// Exportação para HTML autônomo e PDF, e impressão. Usa um WKWebView fora da tela.
final class Exporter: NSObject, WKNavigationDelegate {
    private static var active = Set<Exporter>()

    private let webView: WKWebView
    private let window: NSWindow
    private var onLoad: (() -> Void)?

    private override init() {
        let frame = NSRect(x: 0, y: 0, width: 820, height: 1100)
        webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentView = webView
        webView.navigationDelegate = self
    }

    private func finish() {
        webView.navigationDelegate = nil
        Exporter.active.remove(self)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let cb = onLoad
        onLoad = nil
        // Pequena folga para imagens e fontes assentarem.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { cb?() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write("Marcado: falha provisória: \(error)\n".data(using: .utf8)!)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        FileHandle.standardError.write("Marcado: processo web terminou\n".data(using: .utf8)!)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Marcado: falha ao carregar exportação: \(error)")
    }

    // MARK: - Markdown -> HTML

    /// Converte Markdown no corpo HTML usando o mesmo markdown-it do preview.
    static func renderBody(markdown: String, completion: @escaping (String?) -> Void) {
        let ex = Exporter()
        active.insert(ex)
        ex.onLoad = { [ex] in
            ex.webView.callAsyncJavaScript("return marcado.renderHTML(t)", arguments: ["t": markdown], in: nil, in: .page) { result in
                ex.finish()
                switch result {
                case .success(let v): completion(v as? String)
                case .failure(let e): NSLog("Marcado: render falhou: \(e)"); completion(nil)
                }
            }
        }
        ex.webView.loadFileURL(AppResources.previewURL, allowingReadAccessTo: AppResources.webDirectory)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Página HTML completa, com o CSS do tema embutido e sem scripts.
    static func standaloneHTML(body: String, title: String, appearance: NSAppearance, forPrint: Bool = false) -> String {
        let s = Settings.previewSettings(appearance: appearance)
        let theme = s["theme"] as? String ?? "claro"
        let font = (s["font"] as? String ?? "").replacingOccurrences(of: "\"", with: "'")
        let size = forPrint ? max(11, (s["size"] as? Int ?? 19) - 7) : (s["size"] as? Int ?? 19)
        let width = s["width"] as? Int ?? 720
        let lh = s["lh"] as? Double ?? 1.65
        let style = "--reader-font: \(font); --reader-size: \(size)px; --reader-width: \(width)px; --reader-lh: \(lh);"
        return """
        <!doctype html>
        <html lang="pt-BR" data-theme="\(theme)"\(Settings.wrapCode ? " class=\"wrap-code\"" : "") style="\(style)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Marcado">
        <title>\(escape(title))</title>
        <style>
        \(AppResources.themesCSS)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    static func exportHTML(markdown: String, title: String, appearance: NSAppearance, to url: URL,
                           completion: @escaping (Error?) -> Void) {
        renderBody(markdown: markdown) { body in
            guard let body else { completion(CocoaError(.fileWriteUnknown)); return }
            let html = standaloneHTML(body: body, title: title, appearance: appearance)
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    // MARK: - PDF e impressão

    /// A4 em pontos e margens.
    static let paper = NSSize(width: 595.28, height: 841.89)
    static let marginX: CGFloat = 54
    static let marginY: CGFloat = 50
    static var contentWidth: CGFloat { paper.width - 2 * marginX }
    static var contentHeight: CGFloat { paper.height - 2 * marginY }

    /// Gera um PDF A4 paginado. O WKWebView renderiza um PDF contínuo (createPDF) na largura
    /// útil da página; o JS indica onde quebrar (antes de parágrafos, títulos, linhas de tabela)
    /// e cada fatia é desenhada numa página. Mantém o texto vetorial e selecionável.
    static func makePDF(markdown: String, title: String, baseURL: URL?, appearance: NSAppearance,
                        completion: @escaping (Data?) -> Void) {
        renderBody(markdown: markdown) { body in
            guard let body else { completion(nil); return }
            var html = standaloneHTML(body: body, title: title, appearance: appearance, forPrint: true)
            html = html.replacingOccurrences(of: "<body>", with: "<body class=\"pdf\">")
            let ex = Exporter()
            active.insert(ex)
            ex.webView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
            ex.window.setContentSize(ex.webView.frame.size)
            ex.onLoad = { [ex] in
                let js = """
                const limit = \(contentHeight);
                const els = document.querySelectorAll('.markdown-body > *, .markdown-body li, .markdown-body tr, .markdown-body blockquote > *, .markdown-body pre');
                const tops = new Set();
                els.forEach(e => { const prev = e.previousElementSibling; if (prev && /^H[1-6]$/.test(prev.tagName)) return; const r = e.getBoundingClientRect(); tops.add(Math.floor(r.top + window.scrollY)); });
                const H = Math.ceil(document.documentElement.scrollHeight);
                const cand = Array.from(tops).filter(t => t > 0 && t < H).sort((a, b) => a - b);
                const breaks = [];
                let y = 0;
                while (H - y > limit) {
                  let best = -1;
                  for (const t of cand) { if (t > y + limit * 0.45 && t <= y + limit) best = t; }
                  if (best < 0) best = y + limit;
                  breaks.push(best);
                  y = best;
                }
                return { height: H, breaks: breaks };
                """
                ex.webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                    guard case .success(let v) = result, let info = v as? [String: Any],
                          let height = (info["height"] as? NSNumber)?.doubleValue else {
                        ex.finish(); completion(nil); return
                    }
                    let breaks = (info["breaks"] as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? []
                    let fullHeight = CGFloat(height)
                    ex.webView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: fullHeight)
                    ex.window.setContentSize(ex.webView.frame.size)
                    let cfg = WKPDFConfiguration()
                    cfg.rect = CGRect(x: 0, y: 0, width: contentWidth, height: fullHeight)
                    ex.webView.createPDF(configuration: cfg) { pdfResult in
                        ex.finish()
                        guard case .success(let tall) = pdfResult else { completion(nil); return }
                        let bg = ReaderTheme(rawValue: (Settings.previewSettings(appearance: appearance)["theme"] as? String) ?? "claro")?.palette.bg ?? .white
                        completion(paginate(tall: tall, breaks: breaks, fullHeight: fullHeight, background: bg, title: title))
                    }
                }
            }
            ex.webView.loadHTMLString(html, baseURL: baseURL ?? AppResources.webDirectory)
        }
    }

    private static func paginate(tall: Data, breaks: [CGFloat], fullHeight: CGFloat, background: NSColor, title: String) -> Data? {
        guard let provider = CGDataProvider(data: tall as CFData),
              let src = CGPDFDocument(provider), let page = src.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        // O PDF contínuo pode vir em escala diferente dos pontos CSS; normaliza pela largura.
        let scale = box.width > 0 ? contentWidth / box.width : 1
        let H = box.height * scale

        let out = NSMutableData()
        var media = CGRect(origin: .zero, size: paper)
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &media,
                                  [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Marcado"] as CFDictionary)
        else { return nil }

        let factor = fullHeight > 0 ? H / fullHeight : 1
        let starts = [0] + breaks.map { $0 * factor }
        let ends = breaks.map { $0 * factor } + [H]
        for (y0, y1) in zip(starts, ends) where y1 > y0 {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(background.cgColor)
            ctx.fill(media)
            let sliceH = y1 - y0
            let clip = CGRect(x: marginX, y: paper.height - marginY - sliceH, width: contentWidth, height: sliceH)
            ctx.saveGState()
            ctx.clip(to: clip)
            ctx.translateBy(x: marginX, y: paper.height - marginY - (H - y0))
            ctx.scaleBy(x: scale, y: scale)
            ctx.drawPDFPage(page)
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return out as Data
    }

    static func exportPDF(markdown: String, title: String, baseURL: URL?, appearance: NSAppearance, to url: URL,
                          completion: @escaping (Error?) -> Void) {
        makePDF(markdown: markdown, title: title, baseURL: baseURL, appearance: appearance) { data in
            guard let data else { completion(CocoaError(.fileWriteUnknown)); return }
            do { try data.write(to: url); completion(nil) } catch { completion(error) }
        }
    }

    static func printDocument(markdown: String, title: String, baseURL: URL?, appearance: NSAppearance, window: NSWindow?) {
        makePDF(markdown: markdown, title: title, baseURL: baseURL, appearance: appearance) { data in
            guard let data, let doc = PDFDocument(data: data) else { NSSound.beep(); return }
            let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
            info.paperSize = paper
            info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
            guard let op = doc.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) else { return }
            op.jobTitle = title
            if let window { op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
        }
    }
}
