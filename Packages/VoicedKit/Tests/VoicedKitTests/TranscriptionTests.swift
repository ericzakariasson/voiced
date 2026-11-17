import Foundation
import Testing
@testable import VoicedKit

@Suite struct STTServerEventTests {
    private func decode(_ json: String) throws -> STTServerEvent {
        try STTServerEvent.decode(Data(json.utf8))
    }

    // The JSON below is copied from the examples in docs.x.ai/stt-streaming.ws.json.

    @Test func decodesCreated() throws {
        let event = try decode(#"{"type": "transcript.created", "id": "83f2f6fd-1cd1-4747-bc52-cebddc961c32"}"#)
        #expect(event == .created)
    }

    @Test func decodesPartialUsingWordTimings() throws {
        let event = try decode("""
            {"type": "transcript.partial", "text": "The balance is $167,983.15.", "words": [{"text": "The", "start": 0.24, "end": 0.48, "confidence": 0.95}, {"text": "balance", "start": 0.48, "end": 0.96, "confidence": 0.92}, {"text": "is", "start": 0.96, "end": 1.12, "confidence": 0.98}, {"text": "$167,983.15.", "start": 1.12, "end": 3.2, "confidence": 0.89}], "is_final": true, "speech_final": false, "start": 0.0, "duration": 3.2}
            """)
        #expect(event == .partial(.init(text: "The balance is $167,983.15.", isFinal: true, range: 0.24...3.2)))
    }

    @Test func partialWithoutWordsFallsBackToStartAndDuration() throws {
        let event = try decode(#"{"type": "transcript.partial", "text": "hello", "words": [], "is_final": false, "speech_final": false, "start": 1.5, "duration": 2.0}"#)
        #expect(event == .partial(.init(text: "hello", isFinal: false, range: 1.5...3.5)))
    }

    @Test func decodesDone() throws {
        #expect(try decode(#"{"type": "transcript.done", "text": "", "words": [], "duration": 6.43}"#) == .done(.init(text: "")))
        let withWords = try decode(#"{"type": "transcript.done", "text": "Hi there", "words": [{"text": "Hi", "start": 0.2, "end": 0.4}, {"text": "there", "start": 0.4, "end": 0.9}], "duration": 1.0}"#)
        #expect(withWords == .done(.init(text: "Hi there", range: 0.2...0.9)))
    }

    @Test func decodesError() throws {
        let event = try decode(#"{"type": "error", "message": "Invalid message: expected {\"type\": \"audio.done\"}"}"#)
        #expect(event == .error(message: #"Invalid message: expected {"type": "audio.done"}"#))
    }

    @Test func keepsUnknownTypes() throws {
        #expect(try decode(#"{"type": "transcript.something_new"}"#) == .unknown(type: "transcript.something_new"))
    }

    @Test func rejectsNonEvents() {
        #expect(throws: (any Error).self) { try decode("not json") }
    }
}

@Suite struct TranscriptAssemblerTests {
    private func final(_ text: String, _ range: ClosedRange<Double>) -> STTServerEvent.Partial {
        .init(text: text, isFinal: true, range: range)
    }

    @Test func joinsFinalChunksInOrder() {
        var assembler = TranscriptAssembler()
        assembler.apply(final("Hello there.", 0.2...2.9))
        assembler.apply(final("How are you?", 3.1...5.8))

        #expect(assembler.text == "Hello there. How are you?")
    }

    @Test func ignoresInterimResults() {
        var assembler = TranscriptAssembler()
        assembler.apply(.init(text: "Hel", isFinal: false, range: 0...0.5))

        #expect(assembler.text == "")
    }

    @Test func aStitchedUtteranceReplacesTheChunksItCovers() {
        var assembler = TranscriptAssembler()
        assembler.apply(final("hello there", 0.2...2.9))
        assembler.apply(final("how are you", 3.1...5.8))
        assembler.apply(final("Hello there, how are you?", 0.2...5.8))
        assembler.apply(final("Fine, thanks.", 7.0...8.0))

        #expect(assembler.text == "Hello there, how are you? Fine, thanks.")
    }

    @Test func aRepeatOfAnAlreadyCoveredChunkIsDropped() {
        var assembler = TranscriptAssembler()
        assembler.apply(final("Hello there, how are you?", 0.2...5.8))
        assembler.apply(final("how are you", 3.1...5.8))

        #expect(assembler.text == "Hello there, how are you?")
    }

    @Test func aLaterResultForTheSameAudioWins() {
        var assembler = TranscriptAssembler()
        assembler.apply(final("hello their", 0.2...2.9))
        assembler.apply(final("Hello there.", 0.21...2.88))

        #expect(assembler.text == "Hello there.")
    }

    @Test func doneWithTheFullTranscriptReplacesTheChunks() {
        var assembler = TranscriptAssembler()
        assembler.apply(final("hello there", 0.2...2.9))
        assembler.apply(final("how are you", 3.1...5.8))

        #expect(assembler.finish(with: .init(text: "Hello there. How are you?", range: 0.2...5.8)) == "Hello there. How are you?")
    }

    @Test func doneWithOnlyTheTailIsAppended() {
        var assembler = TranscriptAssembler()
        assembler.apply(final("Hello there.", 0.2...2.9))

        #expect(assembler.finish(with: .init(text: "How are you?", range: 3.1...5.8)) == "Hello there. How are you?")
    }

    @Test func emptyDoneKeepsTheChunks() {
        var assembler = TranscriptAssembler()
        assembler.apply(final("Hello there.", 0.2...2.9))

        #expect(assembler.finish(with: .init(text: "")) == "Hello there.")
    }

    @Test func doneWithoutTimingsIsTakenAsTheFullTranscript() {
        var assembler = TranscriptAssembler()
        assembler.apply(final("hello there", 0.2...2.9))

        #expect(assembler.finish(with: .init(text: " Hello there. ")) == "Hello there.")
    }

    @Test func blankFinalsAreSkipped() {
        var assembler = TranscriptAssembler()
        assembler.apply(final("Hello.", 0.2...1.0))
        assembler.apply(final("  ", 0.0...5.0))

        #expect(assembler.text == "Hello.")
    }
}

@Suite struct StreamingTranscriptionSessionTests {
    private let created = #"{"type": "transcript.created", "id": "session-1"}"#
    private let audioDone = WebSocketMessage.text(#"{"type":"audio.done"}"#)

    private func makeSession(timeout: Duration = .seconds(5)) -> (StreamingTranscriptionSession, FakeWebSocketConnector) {
        let connector = FakeWebSocketConnector()
        let session = StreamingTranscriptionSession(apiKey: "test-key", connector: connector, finishTimeout: timeout)
        return (session, connector)
    }

    @Test func connectsToTheStreamingEndpointWithTheKey() async throws {
        let (session, connector) = makeSession()
        await session.start()

        let request = try #require(connector.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        #expect(components.scheme == "wss")
        #expect(components.host == "api.x.ai")
        #expect(components.path == "/v1/stt")
        #expect(query == ["model": "grok-voice-transcribe-2.0", "sample_rate": "16000", "encoding": "pcm"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        await session.cancel()
    }

    @Test @MainActor func holdsAudioUntilTheServerIsReadyThenSendsItInOrder() async throws {
        let (session, connector) = makeSession()
        let connection = connector.connection
        await session.start()

        // 250 ms of audio: two full 100 ms chunks and a 50 ms remainder.
        let audio = Data((0..<8000).map { UInt8(truncatingIfNeeded: $0) })
        await session.send(audio: audio.prefix(5000))
        await session.send(audio: audio.suffix(3000))
        try await Task.sleep(for: .milliseconds(50))
        #expect(connection.sent.isEmpty)

        connection.serverSends(created)
        try await waitUntil { connection.sent.count == 2 }

        let result = Task { try await session.finish() }
        try await waitUntil { connection.sent.count == 4 }
        #expect(connection.sent == [
            .data(audio.subdata(in: 0..<3200)),
            .data(audio.subdata(in: 3200..<6400)),
            .data(audio.subdata(in: 6400..<8000)),
            audioDone,
        ])

        connection.serverSends(#"{"type": "transcript.partial", "text": "hello world", "words": [{"text": "hello", "start": 0.1, "end": 0.4}, {"text": "world", "start": 0.4, "end": 0.8}], "is_final": true, "speech_final": true, "start": 0.0, "duration": 0.8}"#)
        connection.serverSends(#"{"type": "transcript.done", "text": "Hello world.", "words": [{"text": "Hello", "start": 0.1, "end": 0.4}, {"text": "world.", "start": 0.4, "end": 0.8}], "duration": 0.25}"#)

        let transcription = try await result.value
        #expect(transcription == TranscriptionResult(text: "Hello world.", isComplete: true))
        #expect(connection.isClosed)
    }

    @Test @MainActor func usesTheChunksWhenDoneCarriesNoText() async throws {
        let (session, connector) = makeSession()
        let connection = connector.connection
        await session.start()
        connection.serverSends(created)

        let result = Task { try await session.finish() }
        connection.serverSends(#"{"type": "transcript.partial", "text": "First part.", "words": [], "is_final": true, "speech_final": false, "start": 0.0, "duration": 3.0}"#)
        connection.serverSends(#"{"type": "transcript.partial", "text": "Second part.", "words": [], "is_final": true, "speech_final": true, "start": 3.0, "duration": 2.0}"#)
        connection.serverSends(#"{"type": "transcript.done", "text": "", "words": [], "duration": 5.0}"#)

        let transcription = try await result.value
        #expect(transcription.text == "First part. Second part.")
    }

    @Test(arguments: [
        (401, XAIError.invalidAPIKey),
        // api.x.ai answers a wrong key with 400, and a handshake failure carries no body to tell why.
        (400, XAIError.connectionRefused(status: 400)),
        (429, XAIError.rateLimited),
        (503, XAIError.server(status: 503, message: nil)),
    ])
    func aRefusedHandshakeIsReported(status: Int, expected: XAIError) async throws {
        let (session, connector) = makeSession()
        await session.start()
        connector.connection.serverFails(URLError(.badServerResponse), handshakeStatus: status)

        await #expect(throws: expected) {
            try await session.finish()
        }
    }

    @Test func aDroppedConnectionSurfacesAsANetworkError() async throws {
        let (session, connector) = makeSession()
        await session.start()
        connector.connection.serverSends(created)
        connector.connection.serverFails(URLError(.networkConnectionLost))

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

    @Test func aServerErrorEventFailsTheSession() async throws {
        let (session, connector) = makeSession()
        await session.start()
        connector.connection.serverSends(created)
        connector.connection.serverSends(#"{"type": "error", "message": "pipeline failure"}"#)

        await #expect(throws: XAIError.transcription(message: "pipeline failure")) {
            try await session.finish()
        }
        #expect(connector.connection.isClosed)
    }

    @Test func timingOutWithFinalizedTextReturnsItMarkedIncomplete() async throws {
        let (session, connector) = makeSession(timeout: .milliseconds(100))
        await session.start()
        connector.connection.serverSends(created)
        connector.connection.serverSends(#"{"type": "transcript.partial", "text": "Most of it.", "words": [], "is_final": true, "speech_final": false, "start": 0.0, "duration": 3.0}"#)

        let result = try await session.finish()
        #expect(result == TranscriptionResult(text: "Most of it.", isComplete: false))
    }

    @Test func timingOutWithNothingThrows() async throws {
        let (session, _) = makeSession(timeout: .milliseconds(100))
        await session.start()

        await #expect(throws: XAIError.timedOut) {
            try await session.finish()
        }
    }

    @Test func cancellingEndsAPendingFinish() async throws {
        let (session, connector) = makeSession()
        await session.start()
        connector.connection.serverSends(created)

        let result = Task { try await session.finish() }
        try await Task.sleep(for: .milliseconds(20))
        await session.cancel()

        await #expect(throws: CancellationError.self) {
            try await result.value
        }
        #expect(connector.connection.isClosed)
    }
}
