import Foundation
import Combine

/// A thin wrapper around a large language model API capable of
/// generating context-aware replies.  This implementation uses the
/// OpenAI Chat Completion API but can be adapted to other providers.
final class LLMService {
    /// Shared singleton instance.
    static let shared = LLMService()
    private init() {}

    /// Your API key for the OpenAI service.  Replace this with your own
    /// key (or load it securely from the Keychain).
    private let openAIAPIKey: String = "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"

    /// The base URL for the OpenAI API.
    private let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Maximum number of retry attempts for a single API call when the API
    /// returns a 429 (Too Many Requests) error.  Each retry uses an
    /// exponential backoff with optional jitter to avoid further throttling.
    private let maxRetryAttempts: Int = 3

    /// Base delay (in seconds) for the exponential backoff.  The delay for
    /// the `n`-th retry is `baseRetryDelay * pow(2.0, Double(n))` plus a
    /// small random jitter.
    private let baseRetryDelay: Double = 1.0

    /// A set used to retain Combine subscriptions created during retry logic.
    private var retryCancellables: Set<AnyCancellable> = []

    // MARK: - Public API

    /// Generate a reply (or replies) for a given contact.  When
    /// `multiStep` is true the model produces 2–3 messages; otherwise a
    /// single reply is produced.  If no API key is present the method
    /// returns a canned stub for demonstration.
    func generateReply(
        contact: Contact,
        recentMessages: [Message],
        goal: String,
        multiStep: Bool
    ) -> AnyPublisher<[String], Error> {
        // Offline stub for testing without an API key
        guard !openAIAPIKey.isEmpty else {
            return Deferred {
                Future<[String], Error> { promise in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        let stub: [String]
                        if multiStep {
                            stub = [
                                "Hey \(contact.label), I totally understand where you're coming from.",
                                "Why don't we chat more about this later when we're both free?",
                                "Looking forward to catching up soon!"
                            ]
                        } else {
                            stub = ["Hi \(contact.label), thanks for reaching out – I’ll get back to you shortly."]
                        }
                        promise(.success(stub))
                    }
                }
            }
            .eraseToAnyPublisher()
        }

        // Build the messages for the OpenAI API request
        var requestMessages: [[String: String]] = []
        // System prompt
        let systemPrompt =
            "You are an expert text-conversation assistant. You know how to mimic different people’s tones and help the user craft replies."
        requestMessages.append(["role": "system", "content": systemPrompt])

        // Context: contact label, goal, style embedding, and history
        var context = "Contact: \(contact.label)\nGoal: \(goal)\n"
        if let embedding = contact.styleEmbedding, !embedding.isEmpty {
            let embString = embedding.map { String(format: "%.3f", $0) }.joined(separator: ", ")
            context += "StyleEmbedding: [\(embString)]\n"
        }
        context += "History:\n"
        for msg in recentMessages {
            let prefix = msg.sender == "You" ? "You" : contact.label
            let formattedDate = ISO8601DateFormatter().string(from: msg.timestamp)
            context += "- \(prefix) [\(formattedDate)]: \(msg.body)\n"
        }
        requestMessages.append(["role": "user", "content": context])

        // Instruction
        let instruction: String
        if multiStep {
            instruction = "Please write a sequence of 2–3 messages that achieves the user’s goal. Keep the tone true to how \(contact.label) and the user usually talk."
        } else {
            instruction = "Please write 1 reply that achieves the user’s goal. Keep the tone true to how \(contact.label) and the user usually talk."
        }
        requestMessages.append(["role": "user", "content": instruction])

        let payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": requestMessages,
            "max_tokens": multiStep ? 150 : 80,
            "temperature": 0.7,
            "n": 1
        ]
        return performChatCompletionRequest(with: payload, attempt: 0)
    }

    /// Adjust an existing message according to the user’s instructions.
    func adjustMessage(
        contact: Contact,
        message: String,
        instructions: String
    ) -> AnyPublisher<String, Error> {
        guard !openAIAPIKey.isEmpty else {
            return Deferred {
                Future<String, Error> { promise in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        // Simple offline “adjustment”
                        var adjusted = message
                        let lower = instructions.lowercased()
                        if lower.contains("shorten") || lower.contains("shorter") {
                            adjusted = String(message.prefix(max(10, message.count / 2)))
                        } else if lower.contains("lengthen") || lower.contains("longer") {
                            adjusted = message + "..." + message
                        } else if lower.contains("less aggressive") || lower.contains("softer") {
                            adjusted = message.replacingOccurrences(of: "!", with: ".")
                        }
                        promise(.success(adjusted))
                    }
                }
            }
            .eraseToAnyPublisher()
        }

        var requestMessages: [[String: String]] = []
        let systemPrompt =
            "You are an expert text-conversation assistant. You know how to mimic different people’s tones and help the user refine their messages."
        requestMessages.append(["role": "system", "content": systemPrompt])

        var context = "Contact: \(contact.label)\n"
        if let embedding = contact.styleEmbedding, !embedding.isEmpty {
            let embString = embedding.map { String(format: "%.3f", $0) }.joined(separator: ", ")
            context += "StyleEmbedding: [\(embString)]\n"
        }
        context += "OriginalMessage: \(message)\n"
        context += "Instructions: \(instructions)"
        requestMessages.append(["role": "user", "content": context])

        let instruction =
            "Please rewrite the original message according to the instructions while maintaining the user’s tone and style. Return only the modified message."
        requestMessages.append(["role": "user", "content": instruction])

        let payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": requestMessages,
            "max_tokens": 120,
            "temperature": 0.7,
            "n": 1
        ]
        return performChatCompletionRequest(with: payload, attempt: 0)
            .tryMap { messages in
                if let first = messages.first { return first }
                throw APIError.decodingError
            }
            .eraseToAnyPublisher()
    }

    /// Provide general advice or help for a conversation based on a free-form prompt.
    func textHelp(
        contact: Contact,
        recentMessages: [Message],
        prompt: String
    ) -> AnyPublisher<String, Error> {
        guard !openAIAPIKey.isEmpty else {
            return Deferred {
                Future<String, Error> { promise in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        promise(.success("Here’s a possible approach: \(prompt). Think about their feelings and respond accordingly."))
                    }
                }
            }
            .eraseToAnyPublisher()
        }

        var requestMessages: [[String: String]] = []
        let systemPrompt =
            "You are an expert text-conversation assistant. You know how to mimic different people’s tones and give tailored advice for messaging situations."
        requestMessages.append(["role": "system", "content": systemPrompt])

        var context = "Contact: \(contact.label)\n"
        if let embedding = contact.styleEmbedding, !embedding.isEmpty {
            let embString = embedding.map { String(format: "%.3f", $0) }.joined(separator: ", ")
            context += "StyleEmbedding: [\(embString)]\n"
        }
        context += "RecentMessages:\n"
        for msg in recentMessages {
            let prefix = msg.sender == "You" ? "You" : contact.label
            let formattedDate = ISO8601DateFormatter().string(from: msg.timestamp)
            context += "- \(prefix) [\(formattedDate)]: \(msg.body)\n"
        }
        context += "UserPrompt: \(prompt)"
        requestMessages.append(["role": "user", "content": context])

        let instruction =
            "Based on the context above, please provide the best possible advice or suggested message to help the user. Return just the advice/message."
        requestMessages.append(["role": "user", "content": instruction])

        let payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": requestMessages,
            "max_tokens": 200,
            "temperature": 0.7,
            "n": 1
        ]
        return performChatCompletionRequest(with: payload, attempt: 0)
            .tryMap { messages in
                if let first = messages.first { return first }
                throw APIError.decodingError
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Private Helpers and Types

    private enum APIError: LocalizedError {
        case rateLimited
        case serverError(Int, String?)
        case invalidResponse
        case decodingError

        var errorDescription: String? {
            switch self {
            case .rateLimited:
                return "The request was rate-limited by the API (HTTP 429)."
            case .serverError(let code, let message):
                if let message = message, !message.isEmpty {
                    return "Server returned status code \(code): \(message)"
                } else {
                    return "Server returned status code \(code)."
                }
            case .invalidResponse:
                return "Received an invalid response from the server."
            case .decodingError:
                return "Failed to decode the response from the API."
            }
        }
    }

    /// Core request handler with exponential backoff, jitter, and stored Combine subscriptions
    private func performChatCompletionRequest(with payload: [String: Any], attempt: Int) -> AnyPublisher<[String], Error> {
        var request = URLRequest(url: openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Future<[String], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(APIError.invalidResponse))
                return
            }
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      let data = data else {
                    promise(.failure(APIError.invalidResponse))
                    return
                }

                // Retry on rate-limit (429) with exponential backoff + jitter
                if httpResponse.statusCode == 429 {
                    if attempt < self.maxRetryAttempts {
                        let delay  = self.baseRetryDelay * pow(2.0, Double(attempt))
                        let jitter = Double.random(in: 0...0.5)
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay + jitter) {
                            self.performChatCompletionRequest(with: payload, attempt: attempt + 1)
                                .sink(receiveCompletion: { completion in
                                    if case let .failure(err) = completion {
                                        promise(.failure(err))
                                    }
                                }, receiveValue: { messages in
                                    promise(.success(messages))
                                })
                                .store(in: &self.retryCancellables)
                        }
                    } else {
                        promise(.failure(APIError.rateLimited))
                    }
                    return
                }

                // Handle other non-success status codes
                guard (200...299).contains(httpResponse.statusCode) else {
                    let bodyString = String(data: data, encoding: .utf8)
                    promise(.failure(APIError.serverError(httpResponse.statusCode, bodyString)))
                    return
                }

                // Decode the JSON response
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]] {
                        let messages = choices.compactMap { choice -> String? in
                            if let msg = choice["message"] as? [String: Any],
                               let content = msg["content"] as? String {
                                return content.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            return nil
                        }
                        promise(.success(messages))
                    } else {
                        promise(.failure(APIError.decodingError))
                    }
                } catch {
                    promise(.failure(APIError.decodingError))
                }
            }
            task.resume()
        }
        .eraseToAnyPublisher()
    }
}
