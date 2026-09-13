# Marcado

**Leitor e editor de Markdown nativo para macOS.** Abre seus arquivos `.md` com uma leitura
bonita, no estilo de site de notícias, e deixa editar quando precisa. Guarda o que você escreveu
mesmo sem salvar e, ao abrir de novo, volta exatamente de onde você parou.

Somente para macOS 14 Sonoma ou mais novo (inclui macOS 26). Feito em Swift e AppKit, sem Electron,
sem servidor, sem conta e sem nenhuma conexão de rede.

![Marcado no tema Sépia, com editor e visualização lado a lado](docs/dividido.png)

![Modo leitura no tema Meia-noite, com a barra lateral de documentos](docs/leitura.png)

> **English summary.** Marcado is a native macOS (14+) Markdown reader and editor written in
> Swift/AppKit. It opens plain `.md` files in tabs with a live preview and news-site style reading
> themes (Light, Sepia, Dark, Midnight) and a choice of fonts, size, column width and line height.
> Like Sublime Text, it restores your last session on launch, including never-saved notes, which
> survive quitting, rebooting and even a crash. A VS Code style sidebar lists open and recent
> documents. Also: formatting toolbar and shortcuts, find and replace, focus and typewriter modes,
> word count and reading time, HTML and paginated A4 PDF export. MIT licensed, commercial use
> allowed. Build with `./build-app.sh --install` (needs Xcode or Swift 5.9+). UI in Portuguese.

## Por que existe

A maioria dos editores de Markdown ou é pesada (Electron), ou é feita para escrever e não para
ler, ou esquece o que você digitou se não salvar. O Marcado junta três coisas: leitura
confortável de arquivos `.md` comuns, edição simples quando precisa, e a sessão que nunca se perde,
do jeito que o Sublime Text faz. Foi inspirado no FrankMD
([github.com/akitaonrails/FrankMD](https://github.com/akitaonrails/FrankMD)), mas é um app de
documentos do Mac, sem pasta de notas obrigatória, sem banco e sem servidor.

## O que faz

**Ler**
- Visualização renderizada com tipografia de leitura: títulos, listas, listas de tarefas,
  citações, tabelas, blocos de código com botão Copiar, imagens relativas ao arquivo e links.
- Temas: Claro (branco), Sépia (amarelado, estilo jornal), Escuro, Meia-noite e Automático, que
  segue o claro/escuro do sistema. O editor acompanha o tema.
- 9 fontes de leitura já presentes no macOS (New York, Georgia, Charter, Palatino, Iowan Old Style,
  San Francisco, Avenir Next, Helvetica Neue, SF Mono) e 5 fontes para o editor.
- Tamanho do texto, largura da coluna (estreita, média, larga) e entrelinha (compacta, normal, ampla).
- Três modos: só editor, editor e visualização lado a lado (com rolagem sincronizada) e só leitura.

**Abrir e organizar**
- Documentos em abas, como no Safari. Duplo clique no Finder abre no Marcado.
- Barra lateral no estilo do Explorador do VS Code: documentos abertos e recentes, com filtro,
  menu de contexto (Mostrar no Finder, Copiar caminho, Remover dos recentes) e arrastar e soltar.
- Tela de início focada em abrir, quando não há nada aberto.

**Nunca perder texto**
- Ao abrir o app, voltam as mesmas abas, na mesma ordem, com a mesma aba ativa.
- Texto escrito num documento novo, sem salvar, é gravado em disco a cada pausa na digitação.
  A aba leva o nome da primeira linha. O rascunho volta depois de encerrar, reiniciar o Mac ou
  até de o app ser encerrado à força.
- Arquivos já salvos gravam sozinhos (autosave do macOS, com versões e Reverter).

**Editar**
- Realce de sintaxe Markdown no editor.
- Barra de ferramentas e atalhos para negrito, itálico, riscado, código, títulos, citação, listas,
  lista de tarefas, link, imagem, bloco de código, tabela e linha horizontal. Aplicar de novo remove.
- Localizar e substituir, verificação ortográfica, desfazer ilimitado.
- Modo foco (esconde tudo menos o texto) e máquina de escrever (linha atual sempre no meio).
- Contagem de palavras e caracteres, tempo de leitura e posição do cursor.

**Exportar**
- HTML autônomo com o tema escolhido embutido.
- PDF A4 paginado, com texto selecionável, sem cortar linhas nem separar título do parágrafo.
- Impressão.

## Instalar

Não há binário pronto: compile na sua máquina. Requer macOS 14+ e Xcode 15+ (ou Command Line
Tools com Swift 5.9+). Não há Xcode project: é um Swift Package puro.

```sh
git clone https://github.com/cassiorox/marcado.git
cd marcado
./build-app.sh --install   # compila, monta build/Marcado.app, copia para /Applications e abre
```

O app é assinado ad hoc na sua máquina. Para os arquivos `.md` abrirem no Marcado com duplo
clique: menu **Marcado > Definir como app padrão para .md** (ou Finder > Obter informações >
Abrir com > Alterar tudo).

## Uso

| Ação | Atalho |
|---|---|
| Novo, Abrir, Salvar | ⌘N, ⌘O, ⌘S |
| Salvar como (igual ao Sublime), Duplicar | ⇧⌘S, ⌥⇧⌘S |
| Barra lateral (abertos e recentes) | ⌃⌘S |
| Tela de início | ⇧⌘0 |
| Só editor, Dividido, Leitura | ⌘1, ⌘2, ⌘3 |
| Modo foco (Esc sai) | ⇧⌘F |
| Máquina de escrever | ⇧⌘T |
| Aumentar, diminuir, tamanho padrão | ⌘+, ⌘-, ⌘0 |
| Próximo tema | ⌃⌘T |
| Localizar, Localizar e substituir | ⌘F, ⌥⌘F |
| Negrito, itálico, riscado, código | ⌘B, ⌘I, ⇧⌘X, ⌘E |
| Título 1 a 6, texto normal | ⌥⌘1 a ⌥⌘6, ⌥⌘0 |
| Link, imagem | ⌘K, ⇧⌘I |
| Citação, lista, numerada, tarefas | ⇧⌘., ⇧⌘L, ⇧⌘O, ⇧⌘C |
| Bloco de código, tabela, linha horizontal | ⇧⌘K, ⌥⌘T, ⌥⌘- |
| Exportar HTML, exportar PDF, imprimir | ⇧⌘E, ⌥⇧⌘E, ⌘P |
| Barra de status | ⌘/ |

As ações de formatação alternam: aplicar de novo remove. Sem seleção, negrito/itálico pegam a
palavra do cursor e as de linha (título, lista, citação) valem para a linha atual.

Tema, fontes, tamanho, largura e entrelinha ficam no menu **Visualizar** e no botão "Aa" da barra;
valem para todas as janelas e são lembrados. O tema Automático segue o claro/escuro do sistema.

O salvamento é o padrão do macOS (autosave com versões): o arquivo em disco é atualizado
sozinho, e Arquivo > Reverter volta à última versão salva.

## Sessão e rascunhos (como o Sublime Text)

- Ao abrir, o app volta exatamente como estava: mesmas abas, na mesma ordem, com a mesma aba ativa.
  Sem sessão anterior, aparece a tela de início (abrir documento, recentes, arrastar arquivo).
  O app nunca abre um documento em branco sozinho.
- Texto escrito num documento novo, sem salvar, fica guardado. A aba leva o nome da primeira
  linha e mostra um ponto de "não salvo". Ele volta ao reabrir o app, depois de desligar o Mac e
  até depois de o app ser encerrado à força, porque é gravado em disco a cada pausa na digitação.
- Encerrar o app (⌘Q) não pergunta nada. Fechar a aba de um rascunho (⌘W) pergunta se quer
  salvar. Se escolher apagar, o texto ainda fica 30 dias em `Descartados`.
- Arquivos em `~/Library/Application Support/Marcado/`: `sessao.json` (abas), `Rascunhos/`
  (um `.md` por rascunho aberto) e `Descartados/`. São texto puro, sem criptografia.
- A barra lateral (⌃⌘S) lista os documentos abertos e os recentes, com filtro. Clique abre;
  o botão direito tem Mostrar no Finder, Copiar caminho e Remover dos recentes. Dá para
  arrastar arquivos para ela. A largura é ajustável e fica lembrada.

## Linha de comando

```sh
M=/Applications/Marcado.app/Contents/MacOS/Marcado
$M --export-html entrada.md saida.html [--tema claro|sepia|escuro|meianoite]
$M --export-pdf  entrada.md saida.pdf  [--tema ...]
$M --selftest    # formatação, documento, sessão e rascunhos (usa pasta temporária)
# MARCADO_DEBUG=1 liga o log da sessão; MARCADO_SUPPORT_DIR=/tmp/x isola sessão e recentes
```

## Arquitetura

```
Sources/Marcado/
  main.swift                  entrada; modos --export-* e --selftest rodam ANTES do NSApp.run
  AppDelegate.swift           menus, ações globais de aparência, app padrão, CLI
  Settings.swift              UserDefaults + notificação Settings.didChange; AppResources (pasta web)
  Theme.swift                 temas (paleta do editor), fontes, largura, entrelinha, ViewMode
  Document.swift              NSDocument (MarkdownDocument): texto UTF-8, autosave em local
  DocumentWindowController.swift  janela, NSToolbar, NSSplitView editor|preview, modos, foco, exportar
  StatusBar.swift             palavras, caracteres, tempo de leitura (200 ppm), linha/coluna
  SelfTest.swift              autoteste sem UI
  WelcomeWindowController.swift  tela de início (sem documentos abertos)
  Session/SessionStore.swift  sessão, rascunhos, recentes; MarcadoDocumentController
  Sidebar/SidebarView.swift   barra lateral (abertos e recentes) e ThemedSplitView
  Editor/MarkdownTextView.swift   NSTextView TextKit 1, largura máxima, máquina de escrever, linhas
  Editor/SyntaxHighlighter.swift  realce por regex no NSTextStorageDelegate (parágrafo editado)
  Editor/Formatter.swift          ações de formatação com desfazer
  Preview/PreviewView.swift       WKWebView com preview.html, render com atraso, rolagem sincronizada
  Preview/Exporter.swift          HTML autônomo e PDF A4 paginado
Resources/
  Info.plist                  tipos de documento (net.daringfireball.markdown, texto simples)
  web/preview.html            página do preview (CSP bloqueia scripts do documento)
  web/preview.js              markdown-it + listas de tarefas + data-line para rolagem sincronizada
  web/themes.css              temas e tipografia de leitura (cores iguais às de Theme.swift)
  web/markdown-it.min.js      markdown-it 14.1.0 (MIT), offline
make-icon.swift               gera Resources/AppIcon.icns
```

## Armadilhas

- **Argumentos de linha de comando viram documentos.** Rodando dentro do `.app`, o
  NSDocumentController tenta abrir os caminhos passados na linha de comando e trava num alerta
  invisível. Por isso os modos `--export-*` e `--selftest` rodam em `main.swift` antes do `NSApp.run()`.
- **PDF não usa NSPrintOperation do WKWebView.** Fora da tela ela entra em loop e gera PDF de
  centenas de MB. O Exporter usa `createPDF` (uma página contínua na largura útil do A4) e fatia em
  páginas no CoreGraphics, quebrando antes de parágrafos, itens e linhas de tabela (nunca logo
  depois de um título). O texto continua vetorial.
- **Cores em dois lugares:** `Theme.swift` (editor) e `web/themes.css` (preview e exportação).
  Tema novo exige mexer nos dois.
- **Editor em TextKit 1** (NSLayoutManager explícito) para ter geometria de linha estável na
  máquina de escrever e na rolagem sincronizada.
- O scroll view do editor tem `automaticallyAdjustsContentInsets = false`; sem isso ele abria
  rolado 28 pt para baixo.
- O realce recalcula o documento inteiro quando a edição envolve cercas de código (```` ``` ````)
  ou colagens grandes; do contrário só o parágrafo editado.
- **Sessão é do app, não do sistema.** A restauração de janelas do macOS fica desligada
  (`NSQuitAlwaysKeepsWindows`) e as janelas não são restauráveis; senão as abas duplicam.
- **Encerrar sem alerta:** `MarcadoDocumentController.reviewUnsavedDocuments` grava a sessão e zera a
  marca de alterado dos rascunhos já gravados em disco antes do AppKit revisar documentos. Se o
  encerramento for cancelado, a marca volta em 3 s.
- Rascunho que nasce com texto (Duplicar, restauração) precisa atualizar nome e cópia em disco em
  `makeWindowControllers`, porque não passa pela digitação.
- O primeiro `NSDocumentController` criado vira o compartilhado: `main.swift` cria o
  `MarcadoDocumentController` antes de qualquer acesso a `NSDocumentController.shared`.
- A barra de ferramentas guarda a configuração por identificador. Item novo na barra exige trocar
  o identificador (hoje `MarcadoToolbar2`), senão quem já usou o app não vê o item.

## Licença

MIT. Pode usar, copiar, modificar, distribuir, sublicenciar e **vender**, inclusive em produtos
comerciais e de código fechado, desde que o aviso de copyright e a licença acompanhem as cópias.
Veja [LICENSE](LICENSE).

O markdown-it incluído em `Resources/web/markdown-it.min.js` é de outros autores, também sob licença
MIT (github.com/markdown-it/markdown-it).

Projeto pessoal de Cassio Prado. Não há suporte formal, mas issues e pull requests são bem-vindos.
