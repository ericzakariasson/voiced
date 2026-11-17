import Foundation
import Testing
@testable import VoicedKit

/// Runs the real `URLSession` WebSocket transport against a local server that follows the
/// documented protocol. This covers everything short of xAI's own servers.
@Suite struct StreamingTransportTests {
    private func configuration(for url: URL) -> XAIConfiguration {
        var configuration = XAIConfiguration.default
        configuration.streamingTranscriptionURL = url
        return configuration
    }

    @Test func streamsAudioOverARealWebSocketAndReturnsTheTranscript() async throws {
        let server = try LocalSTTServer(transcript: "Hello from the local server.")
        defer { server.stop() }
        let url = try await server.start()

        let session = StreamingTranscriptionSession(apiKey: "local-test-key", configuration: configuration(for: url))
        await session.start()

        // One second of audio, handed over in uneven pieces the way a microphone tap delivers it.
        let audio = Data((0..<32_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        var offset = 0
        while offset < audio.count {
            let end = min(offset + 1411, audio.count)
            await session.send(audio: audio.subdata(in: offset..<end))
            offset = end
        }

        let result = try await session.finish()

        #expect(result == TranscriptionResult(text: "Hello from the local server.", isComplete: true))
        let recording = server.snapshot()
        #expect(!recording.audioArrivedBeforeReady)
        #expect(recording.audioFrames.count == 10)
        #expect(recording.audioFrames.allSatisfy { $0.count == 3200 })
        #expect(recording.audioFrames.reduce(Data(), +) == audio)
        #expect(recording.textMessages == [#"{"type":"audio.done"}"#])
    }

    @Test func theUpgradeRequestCarriesTheKeyAndTheStreamSettings() async throws {
        let server = try RequestCapturingServer()
        defer { server.stop() }
        let url = try await server.start()

        let session = StreamingTranscriptionSession(apiKey: "local-test-key", configuration: configuration(for: url))
        await session.start()
        let request = try #require(await server.firstRequest())
        await session.cancel()

        let lines = request.components(separatedBy: "\r\n")
        #expect(lines.first == "GET /v1/stt?model=grok-voice-transcribe-2.0&sample_rate=16000&encoding=pcm HTTP/1.1")
        #expect(lines.contains("Authorization: Bearer local-test-key"))
        #expect(lines.contains("Upgrade: websocket"))
    }

    @Test func failsWhenNothingIsListening() async throws {
        let server = try LocalSTTServer(transcript: "")
        let url = try await server.start()
        server.stop()
        try await Task.sleep(for: .milliseconds(100))

        let session = StreamingTranscriptionSession(apiKey: "k", configuration: configuration(for: url))
        await session.start()

        do {
            _ = try await session.finish()
            Issue.record("finish() should have thrown")
        } catch let error as XAIError {
            guard case .network = error else {
                Issue.record("unexpected error \(error)")
                return
            }
        }
    }
}
