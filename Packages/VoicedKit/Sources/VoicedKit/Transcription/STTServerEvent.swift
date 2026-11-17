import Foundation

/// Server messages of the streaming speech-to-text WebSocket (`wss://api.x.ai/v1/stt`).
public enum STTServerEvent: Equatable, Sendable {
    /// The server is ready; audio may be sent from now on.
    case created
    case partial(Partial)
    /// The final transcript, sent after the client's `audio.done`.
    case done(Done)
    case error(message: String)
    case unknown(type: String)

    public struct Partial: Equatable, Sendable {
        public var text: String
        /// `false` means the text may still change.
        public var isFinal: Bool
        /// The stretch of audio this result covers, in seconds from the start of the stream.
        public var range: ClosedRange<Double>

        public init(text: String, isFinal: Bool, range: ClosedRange<Double>) {
            self.text = text
            self.isFinal = isFinal
            self.range = range
        }
    }

    public struct Done: Equatable, Sendable {
        public var text: String
        /// The stretch of audio the text covers, when the server sent word timings.
        public var range: ClosedRange<Double>?

        public init(text: String, range: ClosedRange<Double>? = nil) {
            self.text = text
            self.range = range
        }
    }

    public static func decode(_ data: Data) throws -> STTServerEvent {
        let raw = try JSONDecoder().decode(RawEvent.self, from: data)
        switch raw.type {
        case "transcript.created":
            return .created
        case "transcript.partial":
            let start = raw.start ?? 0
            let fallback = start...(start + max(0, raw.duration ?? 0))
            return .partial(Partial(
                text: raw.text ?? "",
                isFinal: raw.is_final ?? false,
                range: raw.wordRange ?? fallback
            ))
        case "transcript.done":
            return .done(Done(text: raw.text ?? "", range: raw.wordRange))
        case "error":
            return .error(message: raw.message ?? "Unknown error")
        default:
            return .unknown(type: raw.type)
        }
    }

    private struct RawEvent: Decodable {
        var type: String
        var text: String?
        var is_final: Bool?
        var start: Double?
        var duration: Double?
        var words: [RawWord]?
        var message: String?

        /// Start of the first word to the end of the last. Word timings line up across results,
        /// unlike `start` and `duration`, which also count leading silence.
        var wordRange: ClosedRange<Double>? {
            guard let first = words?.first?.start, let last = words?.last?.end, last >= first else {
                return nil
            }
            return first...last
        }
    }

    private struct RawWord: Decodable {
        var start: Double?
        var end: Double?
    }
}
