import AppKit

/// Pedidos prontos do menu IA. O texto do pedido aparece no painel e pode ser editado antes de gerar.
enum AIAction: Int, CaseIterable {
    case resumir, topicos, melhorar, corrigir, encurtar, prompt, tarefas, explicar, continuar, ingles

    var title: String {
        switch self {
        case .resumir: return "Resumir"
        case .topicos: return "Organizar em tópicos"
        case .melhorar: return "Melhorar a redação"
        case .corrigir: return "Corrigir ortografia e gramática"
        case .encurtar: return "Deixar mais curto"
        case .prompt: return "Transformar em prompt"
        case .tarefas: return "Extrair tarefas"
        case .explicar: return "Explicar e aprofundar"
        case .continuar: return "Continuar escrevendo"
        case .ingles: return "Traduzir para inglês"
        }
    }

    var instruction: String {
        switch self {
        case .resumir: return "Resuma o texto em poucos parágrafos curtos, mantendo os pontos principais."
        case .topicos: return "Reorganize o texto em tópicos, com títulos e listas, sem perder nenhuma informação."
        case .melhorar: return "Reescreva o texto com redação mais clara e fluida, mantendo o sentido e o tom."
        case .corrigir: return "Corrija ortografia, gramática e pontuação. Não mude o estilo nem o conteúdo."
        case .encurtar: return "Deixe o texto mais curto e direto, mantendo o essencial."
        case .prompt: return "Transforme o texto num prompt claro e completo para usar com uma IA: objetivo, contexto, o que entregar, formato e restrições. Devolva só o prompt."
        case .tarefas: return "Extraia as tarefas e os próximos passos do texto como lista de tarefas em Markdown (- [ ] ...)."
        case .explicar: return "Explique o texto de forma simples e acrescente informações úteis sobre o assunto."
        case .continuar: return "Continue o texto no mesmo estilo, a partir de onde ele parou. Devolva só a continuação."
        case .ingles: return "Traduza o texto para o inglês, mantendo a formatação Markdown."
        }
    }

    /// Resultado que normalmente entra depois do texto em vez de substituí-lo.
    var insertsBelow: Bool { [.tarefas, .continuar, .explicar].contains(self) }
}

extension MarkdownTextView {

    static let aiSystemPrompt = """
    Você é um assistente de escrita dentro do Marcado, um editor de Markdown para Mac. \
    Responda em português do Brasil, a menos que o pedido indique outro idioma. \
    Devolva só o resultado em Markdown, pronto para entrar na nota, sem introdução, \
    sem comentários sobre o que foi feito e sem cercar a resposta com ```.
    """

    /// Menu IA (barra de menus e botão direito). tag = AIAction.rawValue.
    static func aiMenu() -> NSMenu {
        let m = NSMenu(title: "IA")
        m.addItem(AppDelegate.item("Perguntar à IA…", #selector(aiAsk(_:)), "j", [.command, .option]))
        m.addItem(.separator())
        for a in AIAction.allCases {
            m.addItem(AppDelegate.item(a.title, #selector(aiRun(_:)), tag: a.rawValue))
            if a == .encurtar || a == .explicar { m.addItem(.separator()) }
        }
        m.addItem(.separator())
        m.addItem(AppDelegate.item("Ajustes de IA…", #selector(AppDelegate.showSettings(_:))))
        return m
    }

    /// Trecho selecionado ou, sem seleção, a nota inteira.
    private func aiTarget() -> (range: NSRange, isSelection: Bool) {
        let sel = selectedRange()
        if sel.length > 0 { return (sel, true) }
        return (NSRange(location: 0, length: (string as NSString).length), false)
    }

    @objc func aiAsk(_ sender: Any?) { openAIPanel(action: nil) }

    @objc func aiRun(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        openAIPanel(action: AIAction(rawValue: tag))
    }

    private func openAIPanel(action: AIAction?) {
        guard let window else { return }
        let target = aiTarget()
        let text = (string as NSString).substring(with: target.range)
        if action != nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            NSSound.beep()
            return
        }
        let panel = AIPanelController(textView: self, action: action, range: target.range,
                                      isSelection: target.isSelection, note: string)
        panel.present(on: window)
    }
}
