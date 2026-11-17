import AppKit
import Foundation
import Testing
@testable import VoicedKit

@MainActor
private final class ScriptedCapture: AudioCapturing {
    private let chunks: [AudioChunk]
    private var continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation?

    init(chunks: [AudioChunk]) {
        self.chunks = chunks
    }

    func start() -> AsyncThrowingStream<AudioChunk, any Error> {
        let (stream, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream()
        chunks.forEach { continuation.yield($0) }
        self.continuation = continuation
        return stream
    }

    func stop() {
        continuation?.finish()
    }
}

/// The real controller, streaming session, WebSocket transport, cleaner and pasteboard inserter
/// working together. Only the edges are stand-ins: scripted audio instead of a microphone, a local
/// server instead of xAI's, and a recorded paste instead of a keystroke.
@MainActor
@Suite struct DictationLoopIntegrationTests {
    @Test func aDictationTravelsFromAudioToThePasteboard() async throws {
        let rawTranscript = "um so lets ship it on friday no wait monday"
        let server = try LocalSTTServer(transcript: rawTranscript)
        defer { server.stop() }
        var configuration = XAIConfiguration.default
        configuration.streamingTranscriptionURL = try await server.start()

        let cleanerTransport = FakeHTTPTransport(.response(status: 200, body: """
            {"status": "completed", "output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Let's ship it on Monday."}]}]}
            """))

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)
        var pasted: [String] = []
        let inserter = PasteboardTextInserter(pasteboard: pasteboard, restoreDelay: .milliseconds(30)) {
            pasted.append(pasteboard.string(forType: .string) ?? "")
        }

        // 1.2 seconds of audio in the uneven pieces a microphone tap produces.
        let audio = Data((0..<38_400).map { UInt8(truncatingIfNeeded: $0 &* 13) })
        let chunks = stride(from: 0, to: audio.count, by: 3413).map { start in
            AudioChunk(pcm: audio.subdata(in: start..<min(start + 3413, audio.count)))
        }

        let controller = DictationController(dependencies: .init(
            apiKey: { "local-test-key" },
            makeCapture: { ScriptedCapture(chunks: chunks) },
            makeTranscription: { StreamingTranscriptionSession(apiKey: $0, configuration: configuration) },
            makeCleaner: { TranscriptCleaner(apiKey: $0, configuration: configuration, transport: cleanerTransport) },
            inserter: inserter,
            minimumHold: .zero,
            releaseTail: .milliseconds(20)
        ))

        controller.begin()
        controller.end()
        try await waitUntil { controller.phase == .idle }

        #expect(pasted == ["Let's ship it on Monday."])
        #expect(controller.notice == nil)

        let recording = server.snapshot()
        #expect(recording.audioFrames.reduce(Data(), +) == audio)
        #expect(!recording.audioArrivedBeforeReady)

        let cleanupRequest = try #require(cleanerTransport.requests.first)
        let input = try #require(try jsonObject(cleanupRequest.httpBody)["input"] as? [[String: String]])
        #expect(input.last?["content"] == "<transcript>\n\(rawTranscript)\n</transcript>")

        try await waitUntil { pasteboard.string(forType: .string) == "previous clipboard" }
    }

    /// The same loop with the Cleanup setting off, read from what was saved the way the app
    /// reads it: the transcript reaches the pasteboard as the server sent it, and the cleaner's
    /// transport, which would carry the request to xAI, is never asked for anything.
    @Test func withCleanupSwitchedOffNoCleanupRequestIsSent() async throws {
        let rawTranscript = "um so lets ship it on friday no wait monday"
        let server = try LocalSTTServer(transcript: rawTranscript)
        defer { server.stop() }
        var configuration = XAIConfiguration.default
        configuration.streamingTranscriptionURL = try await server.start()

        let cleanerTransport = FakeHTTPTransport(.response(status: 200, body: """
            {"status": "completed", "output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Let's ship it on Monday."}]}]}
            """))

        let settings = InMemorySettingsStore()
        CleanupSetting(defaults: settings).isOn = false
        let cleanup = CleanupSetting(defaults: settings)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        var pasted: [String] = []
        let inserter = PasteboardTextInserter(pasteboard: pasteboard, restoreDelay: .milliseconds(30)) {
            pasted.append(pasteboard.string(forType: .string) ?? "")
        }

        let controller = DictationController(dependencies: .init(
            apiKey: { "local-test-key" },
            makeCapture: { ScriptedCapture(chunks: [AudioChunk(pcm: Data(repeating: 7, count: 3200))]) },
            makeTranscription: { StreamingTranscriptionSession(apiKey: $0, configuration: configuration) },
            makeCleaner: { TranscriptCleaner(apiKey: $0, configuration: configuration, transport: cleanerTransport) },
            cleanupIsOn: { cleanup.isOn },
            inserter: inserter,
            minimumHold: .zero,
            releaseTail: .milliseconds(20)
        ))

        controller.begin()
        controller.end()
        try await waitUntil { controller.phase == .idle }

        #expect(pasted == [rawTranscript])
        #expect(controller.notice == nil)
        #expect(cleanerTransport.requests.isEmpty)
    }
}
