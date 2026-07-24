import Foundation

public enum AIClientError: Error, LocalizedError {
    case disabled
    case missingConfiguration
    case invalidBaseURL
    case invalidResponse
    /// Model judged the input not a valid English word/phrase.
    case notAWord
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            "AI insights are disabled."
        case .missingConfiguration:
            "AI base URL, API key, and model are required."
        case .invalidBaseURL:
            "AI base URL is invalid."
        case .invalidResponse:
            "AI response could not be read."
        case .notAWord:
            "Not recognized as an English word."
        case .requestFailed(let message):
            message
        }
    }
}

public struct AIClient: Sendable {
    public init() {}

    public func generateInsight(for entry: WordEntry, settings: AppSettings) async throws -> String {
        let content = try await chat(
            settings: settings,
            system: """
            你是一个记忆专家。请输出精简的记忆提示（总计不超过100字），绝不输出多余的寒暄或废话。
            请严格按以下模板输出，替换括号内容：
            🧩 [词根或谐音，30字以内]
            📖 [结合用户身份的搞笑短句，40字以内]
            """ + (entry.fsrs.lapses > 0 ? "\n💡 [一句话易混词辨析，30字以内]" : ""),
            user: "单词：\(entry.word)\n释义：\(entry.meaning)\n用户身份/兴趣：\(settings.userContext.isEmpty ? "无特定背景" : settings.userContext)",
            temperature: 0.7
        )
        return content
    }

    /// Look up an unknown word via the configured AI endpoint when the offline /
    /// online dictionaries have no entry. Returns a `DictionaryResult` suitable
    /// for displaying as a normal word card.
    public func lookupDefinition(for word: String, settings: AppSettings) async throws -> DictionaryResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIClientError.invalidResponse }

        let content = try await chat(
            settings: settings,
            system: """
            你是一本简洁的英汉词典。用户查询一个英文单词或短语。
            若输入不是合理的英语单词或短语（乱码、纯中文、明显无意义），请只输出一行：
            INVALID
            否则严格按以下四行格式输出，不要编号、不要 markdown、不要多余寒暄：
            音标：/IPA/
            中文：词性. 中文释义（可多义，用分号分隔）
            英英：English definition in one or two short sentences
            例句：One natural English example sentence
            """,
            user: "查询单词：\(trimmed)",
            temperature: 0.3
        )

        let stripped = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.uppercased().hasPrefix("INVALID") {
            throw AIClientError.notAWord
        }

        let parsed = Self.parseLookupResponse(content)
        guard !parsed.meaning.isEmpty || !parsed.englishDefinition.isEmpty else {
            throw AIClientError.invalidResponse
        }
        // Soft not-found markers from older model habits.
        if parsed.meaning.contains("未找到") && parsed.englishDefinition.isEmpty {
            throw AIClientError.notAWord
        }
        return parsed
    }

    // MARK: - Shared chat

    private func chat(
        settings: AppSettings,
        system: String,
        user: String,
        temperature: Double
    ) async throws -> String {
        guard settings.aiEnabled else { throw AIClientError.disabled }
        guard !settings.aiBaseURL.isEmpty, !settings.aiAPIKey.isEmpty, !settings.aiModel.isEmpty else {
            throw AIClientError.missingConfiguration
        }

        guard var components = URLComponents(string: settings.aiBaseURL) else {
            throw AIClientError.invalidBaseURL
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))

        guard let url = components.url else { throw AIClientError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.aiAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: settings.aiModel,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ],
            temperature: temperature
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            let message = String(decoding: data, as: UTF8.self)
            throw AIClientError.requestFailed(message)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            throw AIClientError.invalidResponse
        }

        return content
    }

    /// Parse the fixed four-line lookup template into a `DictionaryResult`.
    /// Public for unit tests.
    public static func parseLookupResponse(_ text: String) -> DictionaryResult {
        var phonetic = ""
        var meaning = ""
        var english = ""
        var example = ""

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let value = fieldValue(line, prefixes: ["音标：", "音标:", "Phonetic:", "phonetic:"]) {
                phonetic = value
            } else if let value = fieldValue(line, prefixes: ["中文：", "中文:", "Meaning:", "meaning:"]) {
                meaning = value
            } else if let value = fieldValue(line, prefixes: ["英英：", "英英:", "English:", "english:"]) {
                english = value
            } else if let value = fieldValue(line, prefixes: ["例句：", "例句:", "Example:", "example:"]) {
                example = value
            }
        }

        // Fallback: if the model ignored the template, use the whole text as meaning.
        if meaning.isEmpty && english.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meaning = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return DictionaryResult(
            phonetic: phonetic,
            meaning: meaning,
            englishDefinition: english,
            example: example,
            audioURL: nil
        )
    }

    private static func fieldValue(_ line: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: ChatMessage
    }
}
