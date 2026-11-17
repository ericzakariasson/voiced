import Foundation

/// Endpoints and models for the xAI API, taken from docs.x.ai (checked 2026-11-12).
public struct XAIConfiguration: Sendable, Equatable {
    /// Streaming speech to text: `wss://api.x.ai/v1/stt`.
    public var streamingTranscriptionURL: URL
    /// Responses API: `POST https://api.x.ai/v1/responses`.
    public var responsesURL: URL
    /// Key details, used to check a key when it is saved: `GET https://api.x.ai/v1/api-key`.
    public var apiKeyInfoURL: URL
    public var transcriptionModel: String
    public var cleanupModel: String
    /// Reasoning effort for the cleanup pass. `grok-4.3` accepts `none`, which keeps latency low.
    public var cleanupReasoningEffort: String?
    /// 16 kHz is the transcription model's native rate.
    public var sampleRate: Int

    public init(
        streamingTranscriptionURL: URL = URL(string: "wss://api.x.ai/v1/stt")!,
        responsesURL: URL = URL(string: "https://api.x.ai/v1/responses")!,
        apiKeyInfoURL: URL = URL(string: "https://api.x.ai/v1/api-key")!,
        transcriptionModel: String = "grok-voice-transcribe-2.0",
        cleanupModel: String = "grok-4.3",
        cleanupReasoningEffort: String? = "none",
        sampleRate: Int = 16_000
    ) {
        self.streamingTranscriptionURL = streamingTranscriptionURL
        self.responsesURL = responsesURL
        self.apiKeyInfoURL = apiKeyInfoURL
        self.transcriptionModel = transcriptionModel
        self.cleanupModel = cleanupModel
        self.cleanupReasoningEffort = cleanupReasoningEffort
        self.sampleRate = sampleRate
    }

    public static let `default` = XAIConfiguration()

    /// Bytes in 100 ms of mono 16-bit PCM, the chunk size the streaming docs recommend.
    public var chunkByteCount: Int { sampleRate * 2 / 10 }
}
