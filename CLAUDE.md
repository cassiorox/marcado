# marcado

Editor de Markdown nativo para macOS (Swift 5 mode, AppKit, sem Xcode project). Leia o `README.md`
antes de mexer: arquitetura, atalhos e armadilhas estão lá.

- Compilar e montar o `.app`: `./build-app.sh`; instalar e abrir: `./build-app.sh --install`.
- Verificar antes de entregar: `build/Marcado.app/Contents/MacOS/Marcado --selftest` (rodar pelo
  `.app`, senão os testes de tipo de documento são pulados) e, se mexer em preview/exportação,
  `--export-pdf amostra.md saida.pdf` e conferir as páginas.
- Cores de tema existem em `Theme.swift` e em `Resources/web/themes.css`; mantenha iguais.
- Nada de biblioteca externa de editor (BlockNote, TipTap, CodeMirror etc.) sem combinar antes.
- PT-BR em textos de interface e comentários. Sem emojis.
