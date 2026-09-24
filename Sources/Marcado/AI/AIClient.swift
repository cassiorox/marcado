import Foundation

/// Provedor de IA escolhido nos Ajustes.
enum AIProvider: String, Codable, CaseIterable {
    case claude, openrouter

    var title: String { self == .claude ? "Claude (API da Anthropic)" : "OpenRouter" }
}

/// Chaves e modelos da IA. Ficam em `ia.json` na pasta do app (Application Support/Marcado),
/// com permissão só do usuário (600). Não vão para o Keychain porque o app é assinado ad hoc:
/// cada nova compilação mudaria a identidade e o macOS pediria a senha de novo a cada atualização.
struct AIConfig: Codable, Equatable {
    var provider: AIProvider = .claude
    var claudeKey = ""
    var claudeModel = AIConfig.defaultClaudeModel
    var openRouterKey = ""
    var openRouterModel = AIConfig.defaultOpenRouterModel

    static let defaultClaudeModel = "claude-opus-5"
    static let defaultOpenRouterModel = "anthropic/claude-opus-5"

    static var fileURL: URL { SessionStore.directory.appendingPathComponent("ia.json") }

    static func load() -> AIConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let c = try? JSONDecoder().decode(AIConfig.self, from: data) else { return AIConfig() }
        return c
    }

    func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Self.fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }

    var activeKey: String {
        (provider == .claude ? claudeKey : openRouterKey).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var activeModel: String {
        let m = (provider == .claude ? claudeModel : openRouterModel).trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { return m }
        return provider == .claude ? Self.defaultClaudeModel : Self.defaultOpenRouterModel
    }

    var isReady: Bool { !activeKey.isEmpty }
}

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Chamada com streaming (SSE) direto por HTTP: a API da Anthropic não tem SDK para Swift.
/// Devolve os pedaços de texto conforme chegam.
enum AIClient {
    static func stream(config: AIConfig, system: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard config.isReady else {
                        throw AIError(message: "Nenhuma chave configurada para \(config.provider.title). Abra Marcado > Ajustes.")
                    }
                    let request = try makeRequest(config: config, system: system, prompt: prompt)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw AIError(message: describeHTTPError(status: status, body: body, provider: config.provider))
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let text = try parseEvent(obj, provider: config.provider), !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func makeRequest(config: AIConfig, system: String, prompt: String) throws -> URLRequest {
        let model = config.activeModel
        var req: URLRequest
        var body: [String: Any]
        switch config.provider {
        case .claude:
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(config.activeKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model,
                "max_tokens": 64000,
                "stream": true,
                "system": system,
                "messages": [["role": "user", "content": prompt]],
            ]
            // Se o classificador de segurança recusar, a própria API refaz o pedido no modelo
            // recomendado. Só vale para os modelos que aceitam o modo "default".
            if ["claude-opus-5", "claude-fable-5-1"].contains(model) {
                body["fallbacks"] = "default"
                req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            }
        case .openrouter:
            req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
            req.setValue("Bearer \(config.activeKey)", forHTTPHeaderField: "Authorization")
            req.setValue("https://github.com/cassiorox/marcado", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("Marcado", forHTTPHeaderField: "X-Title")
            body = [
                "model": model,
                "stream": true,
                "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
            ]
        }
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func parseEvent(_ obj: [String: Any], provider: AIProvider) throws -> String? {
        if let err = obj["error"] as? [String: Any] {
            throw AIError(message: (err["message"] as? String) ?? "Erro da API.")
        }
        switch provider {
        case .claude:
            switch obj["type"] as? String {
            case "content_block_delta":
                let delta = obj["delta"] as? [String: Any]
                return delta?["type"] as? String == "text_delta" ? delta?["text"] as? String : nil
            case "message_delta":
                if (obj["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal" {
                    throw AIError(message: "A Claude recusou este pedido. Tente reformular.")
                }
                return nil
            default:
                return nil
            }
        case .openrouter:
            let choice = (obj["choices"] as? [[String: Any]])?.first
            return (choice?["delta"] as? [String: Any])?["content"] as? String
        }
    }

    private static func describeHTTPError(status: Int, body: String, provider: AIProvider) -> String {
        var detail = ""
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
            detail = msg
        }
        let name = provider == .claude ? "Claude" : "OpenRouter"
        switch status {
        case 401, 403: return "Chave da \(name) recusada (\(status)). Confira em Marcado > Ajustes." + (detail.isEmpty ? "" : "\n\(detail)")
        case 404: return "Modelo não encontrado na \(name) (\(status)). Confira o nome do modelo nos Ajustes." + (detail.isEmpty ? "" : "\n\(detail)")
        case 429: return "Limite de uso atingido na \(name) (429). Espere um pouco e tente de novo." + (detail.isEmpty ? "" : "\n\(detail)")
        case 402: return "Sem créditos na \(name) (402)." + (detail.isEmpty ? "" : "\n\(detail)")
        default: return "Erro \(status) da \(name)." + (detail.isEmpty ? "" : "\n\(detail)")
        }
    }
}
