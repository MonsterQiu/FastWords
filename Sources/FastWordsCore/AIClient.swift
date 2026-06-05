import Foundation

public enum AIClientError: Error, LocalizedError {
    case disabled
    case missingConfiguration
    case invalidBaseURL
    case invalidResponse
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
        case .requestFailed(let message):
            message
        }
    }
}

public struct AIClient: Sendable {
    public init() {}

    public func generateInsight(for entry: WordEntry, settings: AppSettings) async throws -> String {
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
                ChatMessage(
                    role: "system",
                    content: "You help Chinese speakers memorize English vocabulary. Keep replies under 80 Chinese characters."
                ),
                ChatMessage(
                    role: "user",
                    content: "单词：\(entry.word)\n释义：\(entry.meaning)\n请给一个幽默但有记忆点的例句或词根提示。"
                )
            ],
            temperature: 0.7
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
