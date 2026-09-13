import AppKit

let app = NSApplication.shared
// O primeiro NSDocumentController criado vira o compartilhado.
_ = MarcadoDocumentController()
// A sessão é do próprio app (SessionStore); a restauração de janelas do sistema duplicaria abas.
UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
let args = CommandLine.arguments

if args.contains("--export-html") || args.contains("--export-pdf") {
    // Modo linha de comando: não passa pelo NSApp.run(), senão o NSDocumentController
    // tenta abrir os caminhos dos argumentos como documentos.
    app.setActivationPolicy(.prohibited)
    AppDelegate.runCommandLine()
    while true { RunLoop.main.run(mode: .default, before: .distantFuture) }
}

if args.contains("--selftest") {
    app.setActivationPolicy(.prohibited)
    exit(SelfTest.run())
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
