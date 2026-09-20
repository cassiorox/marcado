import AppKit

/// `Marcado --selftest`: testa as ações de formatação sem abrir janela.
enum SelfTest {
    static func run() -> Int32 {
        // Sessão e recentes isolados do uso real.
        let tmpSupport = FileManager.default.temporaryDirectory.appendingPathComponent("marcado-selftest-\(getpid())")
        setenv("MARCADO_SUPPORT_DIR", tmpSupport.path, 1)
        SessionStore.recentsKey = "recentFiles-selftest"
        defer {
            try? FileManager.default.removeItem(at: tmpSupport)
            UserDefaults.standard.removeObject(forKey: "recentFiles-selftest")
        }
        var failures = 0
        func check(_ name: String, _ input: String, _ sel: NSRange, _ action: (MarkdownTextView) -> Void, _ expected: String) {
            let (_, tv) = MarkdownTextView.make()
            tv.string = input
            tv.setSelectedRange(sel)
            action(tv)
            if tv.string == expected {
                print("ok   \(name)")
            } else {
                failures += 1
                print("FALHA \(name)\n  esperado: \(expected.debugDescription)\n  obtido:   \(tv.string.debugDescription)")
            }
        }
        let r = { (l: Int, n: Int) in NSRange(location: l, length: n) }

        // Links para pasta/arquivo e imagem colada.
        do {
            let tmp = tmpSupport.appendingPathComponent("Pasta (teste) com espaço", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let file = tmp.appendingPathComponent("relatorio final.pdf")
            FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
            func expect(_ name: String, _ got: String, _ want: String) {
                if got == want { print("ok   \(name)") } else { failures += 1; print("FALHA \(name)\n  esperado: \(want.debugDescription)\n  obtido:   \(got.debugDescription)") }
            }
            expect("link de pasta com espaço", MarkdownTextView.markdownLink(for: tmp), "[Pasta (teste) com espaço](<\(tmp.path)>)")
            expect("link de arquivo relativo ao documento", MarkdownTextView.markdownLink(for: file, relativeTo: tmpSupport),
                   "[relatorio final](<Pasta (teste) com espaço/relatorio final.pdf>)")
            expect("caminho sem espaço fica sem <>", MarkdownTextView.destination(URL(fileURLWithPath: "/tmp/a.txt")), "/tmp/a.txt")

            let pb = NSPasteboard(name: NSPasteboard.Name("marcado-selftest-\(getpid())"))
            pb.clearContents()
            pb.writeObjects([tmp as NSURL])
            let (_, tv) = MarkdownTextView.make()
            tv.string = "antes\n"
            tv.setSelectedRange(r(6, 0))
            expect("cola URL de pasta do Finder como link", tv.insertFromPasteboard(pb) ? tv.string : "(não tratou)", "antes\n[Pasta (teste) com espaço](<\(tmp.path)>)")

            pb.clearContents()
            pb.setString("/nao/existe/caminho", forType: .string)
            expect("texto que não é caminho existente segue normal", tv.insertFromPasteboard(pb) ? "tratou" : "não tratou", "não tratou")

            pb.clearContents()
            pb.setString(tmp.path, forType: .string)
            tv.string = ""
            expect("caminho existente colado como texto vira link", tv.insertFromPasteboard(pb) ? tv.string : "(não tratou)", "[Pasta (teste) com espaço](<\(tmp.path)>)")

            let img = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
            pb.clearContents()
            pb.writeObjects([img])
            let anexos = tmpSupport.appendingPathComponent("Anexos")
            MarkdownTextView.attachmentDirectoryProvider = { _ in anexos }
            tv.string = ""
            let handled = tv.insertFromPasteboard(pb)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: anexos.path)) ?? []
            let ok = handled && files.count == 1 && files[0].hasPrefix("imagem-") && files[0].hasSuffix(".png")
                && tv.string == "![\(files[0].dropLast(4))](\(MarkdownTextView.destination(anexos.appendingPathComponent(files[0]))))"
            expect("imagem colada vira PNG em Anexos + ![]()", ok ? "ok" : "handled=\(handled) files=\(files) texto=\(tv.string)", "ok")
            pb.releaseGlobally()
        }

        check("negrito na seleção", "ola mundo", r(4, 5), { $0.toggleBold(nil) }, "ola **mundo**")
        check("remove negrito (marcas fora)", "ola **mundo**", r(6, 5), { $0.toggleBold(nil) }, "ola mundo")
        check("remove negrito (marcas dentro)", "ola **mundo**", r(4, 9), { $0.toggleBold(nil) }, "ola mundo")
        check("negrito na palavra do cursor", "ola mundo", r(6, 0), { $0.toggleBold(nil) }, "ola **mundo**")
        check("itálico vazio", "", r(0, 0), { $0.toggleItalic(nil) }, "**")
        check("código", "use git", r(4, 3), { $0.toggleInlineCode(nil) }, "use `git`")
        check("riscado", "velho", r(0, 5), { $0.toggleStrikethrough(nil) }, "~~velho~~")
        check("título 2", "Título", r(2, 0), { tv in let m = NSMenuItem(); m.tag = 2; tv.setHeading(m) }, "## Título")
        check("título 2 -> 3", "## Título", r(4, 0), { tv in let m = NSMenuItem(); m.tag = 3; tv.setHeading(m) }, "### Título")
        check("remove título", "## Título", r(4, 0), { tv in let m = NSMenuItem(); m.tag = 2; tv.setHeading(m) }, "Título")
        check("lista em várias linhas", "a\nb\n\nc", r(0, 6), { $0.toggleBulletList(nil) }, "- a\n- b\n\n- c")
        check("remove lista", "- a\n- b", r(0, 7), { $0.toggleBulletList(nil) }, "a\nb")
        check("numerada", "a\nb", r(0, 3), { $0.toggleNumberedList(nil) }, "1. a\n2. b")
        check("lista vira tarefa", "- a", r(3, 0), { $0.toggleTaskList(nil) }, "- [ ] a")
        check("citação", "frase", r(0, 0), { $0.toggleQuote(nil) }, "> frase")
        check("link com texto", "site", r(0, 4), { $0.insertMarkdownLink(nil) }, "[site](https://)")
        check("link com URL", "https://x.com", r(0, 13), { $0.insertMarkdownLink(nil) }, "[](https://x.com)")
        check("imagem vazia", "", r(0, 0), { $0.insertMarkdownImage(nil) }, "![descrição](https://)")
        check("bloco de código em linha vazia", "", r(0, 0), { $0.insertCodeBlock(nil) }, "```\n\n```")
        check("bloco de código na seleção", "x = 1\ny = 2\n", r(0, 11), { $0.insertCodeBlock(nil) }, "```\nx = 1\ny = 2\n```\n")
        check("linha horizontal", "texto", r(5, 0), { $0.insertHorizontalRule(nil) }, "texto\n\n---\n\n")

        // Contagem de palavras
        let words = StatusBarView.countWords("Olá, mundo! Isto é um teste de contagem.")
        if words == 8 { print("ok   contagem de palavras") } else { failures += 1; print("FALHA contagem: \(words)") }

        // Documento: tipo padrão, edição marca alterado, gravação e leitura.
        let dc = NSDocumentController.shared
        if let t = dc.defaultType, t == "net.daringfireball.markdown", dc.documentClass(forType: t) == MarkdownDocument.self {
            print("ok   tipo de documento padrão (\(t))")
            do {
                let doc = try dc.makeUntitledDocument(ofType: t) as! MarkdownDocument
                doc.makeWindowControllers()
                let tv = doc.controller!.textView
                tv.window?.makeFirstResponder(tv)
                tv.insertText("# Olá\n\nTexto **teste**.", replacementRange: NSRange(location: 0, length: 0))
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))  // fecha o grupo de undo
                if tv.undoManager !== doc.undoManager { failures += 1; print("FALHA undo manager não é o do documento") }
                if doc.isDocumentEdited { print("ok   edição marca documento como alterado") }
                else { failures += 1; print("FALHA documento não ficou alterado") }
                tv.undoManager?.undo()
                if tv.string.isEmpty { print("ok   desfazer") } else { failures += 1; print("FALHA desfazer: \(tv.string.debugDescription)") }
                tv.undoManager?.redo()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("marcado-selftest.md")
                try doc.write(to: url, ofType: t)
                let back = try String(contentsOf: url, encoding: .utf8)
                if back == "# Olá\n\nTexto **teste**." { print("ok   gravação UTF-8") } else { failures += 1; print("FALHA gravação: \(back.debugDescription)") }
                let doc2 = MarkdownDocument()
                try doc2.read(from: url, ofType: t)
                if doc2.currentText == back { print("ok   leitura") } else { failures += 1; print("FALHA leitura") }
                try? FileManager.default.removeItem(at: url)
                doc.close()
            } catch {
                failures += 1
                print("FALHA documento: \(error)")
            }
        } else {
            print("aviso: rode pelo .app para testar tipos de documento (defaultType=\(dc.defaultType ?? "nil"))")
        }

        // Sessão: rascunho sem salvar sobrevive a encerrar e reabrir.
        func spin(_ seconds: Double, until: () -> Bool = { false }) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end && !until() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        func expect(_ ok: Bool, _ name: String) {
            if ok { print("ok   \(name)") } else { failures += 1; print("FALHA \(name)") }
        }
        if let t = dc.defaultType {
            do {
                let notes = tmpSupport.deletingLastPathComponent().appendingPathComponent("marcado-notas-\(getpid())")
                try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: notes) }
                let fileURL = notes.appendingPathComponent("nota-teste.md")
                try "# Nota\n\ntexto".write(to: fileURL, atomically: true, encoding: .utf8)
                var opened: NSDocument?
                dc.openDocument(withContentsOf: fileURL, display: false) { d, _, _ in opened = d }
                spin(5) { opened != nil }
                expect(opened != nil, "abrir arquivo")
                expect(SessionStore.recentURLs.contains { $0.standardizedFileURL.path == fileURL.standardizedFileURL.path }, "arquivo entra nos recentes")

                let scratch = try dc.makeUntitledDocument(ofType: t) as! MarkdownDocument
                dc.addDocument(scratch)
                scratch.makeWindowControllers()
                let tv = scratch.controller!.textView
                tv.insertText("Lista de compras\n- pão", replacementRange: NSRange(location: 0, length: 0))
                spin(1.5)
                expect(scratch.displayName == "Lista de compras", "nome do rascunho vem da primeira linha")
                let scratchFile = SessionStore.scratchURL(scratch.scratchID)
                expect((try? String(contentsOf: scratchFile, encoding: .utf8)) == "Lista de compras\n- pão", "rascunho gravado em disco sem salvar")

                let session = SessionStore.saveNow()
                expect(session?.entries.count == 2 && session?.entries.contains { $0.scratch == scratch.scratchID } == true
                       && session?.entries.contains { $0.path == fileURL.path } == true, "sessão lista arquivo e rascunho")

                SessionStore.prepareForTermination()
                expect(!scratch.isDocumentEdited, "encerrar não pede para salvar o rascunho")
                for d in dc.documents { d.close() }
                expect(FileManager.default.fileExists(atPath: scratchFile.path), "rascunho continua em disco após encerrar")
                expect(SessionStore.recentURLs.first?.standardizedFileURL.path == fileURL.standardizedFileURL.path, "arquivo fechado vai para o topo dos recentes")

                SessionStore.isTerminating = false
                var restored = false
                SessionStore.restore { restored = true }
                spin(5) { restored }
                let docs = dc.documents.compactMap { $0 as? MarkdownDocument }
                expect(docs.count == 2, "reabre os 2 documentos (\(docs.count))")
                let back = docs.first { $0.fileURL == nil }
                expect(back?.currentText == "Lista de compras\n- pão", "rascunho volta com o texto")
                expect(back?.isDocumentEdited == true, "rascunho volta marcado como não salvo")
                expect(docs.contains { $0.fileURL?.path == fileURL.path }, "arquivo volta aberto")

                if let back, let dup = try? back.duplicate() as? MarkdownDocument {
                    spin(0.3)
                    expect(dup.displayName == "Lista de compras" && dup.scratchID != back.scratchID
                           && FileManager.default.fileExists(atPath: SessionStore.scratchURL(dup.scratchID).path),
                           "Duplicar gera rascunho com nome e cópia em disco")
                    SessionStore.isTerminating = true
                    dup.close()
                    SessionStore.isTerminating = false
                } else {
                    expect(false, "Duplicar")
                }

                // Rascunho fechado de propósito vai para Descartados.
                SessionStore.isTerminating = false
                if let back {
                    back.close()
                    let discarded = (try? FileManager.default.contentsOfDirectory(atPath: SessionStore.directory.appendingPathComponent("Descartados").path)) ?? []
                    expect(!FileManager.default.fileExists(atPath: SessionStore.scratchURL(back.scratchID).path) && !discarded.isEmpty,
                           "rascunho fechado sem salvar vai para Descartados")
                }
                SessionStore.isTerminating = true
                for d in dc.documents { d.close() }
            } catch {
                failures += 1
                print("FALHA sessão: \(error)")
            }
        }

        print(failures == 0 ? "\nTodos os testes passaram." : "\n\(failures) falha(s).")
        return failures == 0 ? 0 : 1
    }
}
