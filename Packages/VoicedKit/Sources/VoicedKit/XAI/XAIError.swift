import Foundation

public enum XAIError: Error, Equatable, Sendable {
    case invalidAPIKey
    case rateLimited
    case server(status: Int, message: String?)
    /// The streaming connection was turned away. A WebSocket handshake exposes no response body,
    /// so the reason is unknown; xAI answers a wrong key with HTTP 400.
    case connectionRefused(status: Int)
    case transcription(message: String)
    case malformedResponse
    case incompleteResponse
    case timedOut
    case network(description: String)
}

extension XAIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            "The Grok API Key was rejected. Check it in Settings."
        case .rateLimited:
            "xAI rate limit reached. Try again in a moment."
        case let .server(status, message):
            if let message, !message.isEmpty {
                "xAI error \(status): \(message)"
            } else {
                "xAI error \(status)."
            }
        case let .connectionRefused(status):
            "xAI refused the transcription connection (HTTP \(status)). Check your Grok API Key in Settings."
        case let .transcription(message):
            "Transcription failed: \(message)"
        case .malformedResponse:
            "xAI returned a response Voiced could not read."
        case .incompleteResponse:
            "xAI returned an incomplete response."
        case .timedOut:
            "xAI took too long to respond."
        case let .network(description):
            "Network error: \(description)"
        }
    }

    static func fromHTTP(status: Int, body: Data) -> XAIError {
        let message = errorMessage(in: body)
        switch status {
        case 401, 403:
            return .invalidAPIKey
        case 429:
            return .rateLimited
        case 400 where message?.localizedCaseInsensitiveContains("API key") == true:
            // Observed 2026-11-12: a wrong key gets 400 "Incorrect API key provided", not the documented 401.
            return .invalidAPIKey
        default:
            return .server(status: status, message: message)
        }
    }

    /// xAI error bodies carry the message either as `{"error": "..."}` or `{"error": {"message": "..."}}`.
    static func errorMessage(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        if let message = object["error"] as? String {
            return message
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }
}
