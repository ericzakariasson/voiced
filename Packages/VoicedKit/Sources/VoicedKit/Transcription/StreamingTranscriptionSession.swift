import Foundation

private let log = VoicedLog.transcription

public struct TranscriptionResult: Equatable, Sendable {
    public var text: String
    /// `false` when the server did not confirm the end of the stream in time, so the tail may be missing.
    public var isComplete: Bool

    public init(text: String, isComplete: Bool) {
        self.text = text
        self.isComplete = isComplete
    }
}

/// One dictation's worth of streaming transcription.
public protocol TranscriptionSession: Sendable {
    func start() async
    /// Queues mono 16-bit PCM. Call from one task so the audio stays in order.
    func send(audio: Data) async
    /// Signals the end of the audio and waits for the transcript.
    func finish() async throws -> TranscriptionResult
    func cancel() async
}

/// Streams audio to `wss://api.x.ai/v1/stt` and collects the transcript.
///
/// Protocol, per the xAI docs: configuration travels in the query string; the server sends
/// `transcript.created` when it is ready for audio; audio goes up as raw binary frames of about
/// 100 ms; `{"type":"audio.done"}` ends the stream and the server answers with `transcript.done`.
public actor StreamingTranscriptionSession: TranscriptionSession {
    private let request: URLRequest
    private let connector: any WebSocketConnecting
    private let finishTimeout: Duration

    private var chunker: AudioChunker
    private var assembler = TranscriptAssembler()
    private var connection: (any WebSocketConnection)?
    private let outgoing: AsyncStream<WebSocketMessage>
    private let outgoingContinuation: AsyncStream<WebSocketMessage>.Continuation
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var outcome: Result<TranscriptionResult, any Error>?
    private var waiter: CheckedContinuation<TranscriptionResult, any Error>?
    /// Counts for the log, never content.
    private var connectedAt: ContinuousClock.Instant?
    private var queuedFrames = 0
    private var queuedBytes = 0
    private var partialCount = 0
    private var finalCount = 0

    public init(
        apiKey: String,
        configuration: XAIConfiguration = .default,
        connector: any WebSocketConnecting = URLSessionWebSocketConnector(),
        finishTimeout: Duration = .seconds(10)
    ) {
        request = Self.makeRequest(apiKey: apiKey, configuration: configuration)
        self.connector = connector
        self.finishTimeout = finishTimeout
        chunker = AudioChunker(chunkByteCount: configuration.chunkByteCount)
        (outgoing, outgoingContinuation) = AsyncStream<WebSocketMessage>.makeStream()
    }

    static func makeRequest(apiKey: String, configuration: XAIConfiguration) -> URLRequest {
        var components = URLComponents(url: configuration.streamingTranscriptionURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "model", value: configuration.transcriptionModel),
            URLQueryItem(name: "sample_rate", value: String(configuration.sampleRate)),
            URLQueryItem(name: "encoding", value: "pcm"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Bounds the connection attempt. An open socket that goes quiet while the speaker pauses is
        // not subject to it (checked against a silent local server).
        request.timeoutInterval = 15
        return request
    }

    public func start() {
        guard connection == nil, outcome == nil else { return }
        // Host and path only. The key travels in a header and is not logged.
        log.notice("connecting to \(self.request.url?.host() ?? "?", privacy: .public)\(self.request.url?.path() ?? "", privacy: .public)")
        connectedAt = .now
        let connection = connector.connect(request)
        self.connection = connection
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await connection.receive()
                    guard let self, await self.handle(message) else { return }
                } catch {
                    await self?.connectionFailed(error)
                    return
                }
            }
        }
    }

    public func send(audio: Data) {
        guard outcome == nil else { return }
        for chunk in chunker.append(audio) {
            queue(chunk)
        }
    }

    private func queue(_ frame: Data) {
        queuedFrames += 1
        queuedBytes += frame.count
        outgoingContinuation.yield(.data(frame))
    }

    public func finish() async throws -> TranscriptionResult {
        if let outcome {
            return try outcome.get()
        }
        if let remainder = chunker.flush() {
            queue(remainder)
        }
        outgoingContinuation.yield(.text(#"{"type":"audio.done"}"#))
        log.notice("audio.done queued after frames=\(self.queuedFrames) bytes=\(self.queuedBytes); waiting for transcript.done")

        let timeout = finishTimeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.timedOut()
        }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }

    public func cancel() {
        guard outcome == nil else { return }
        // A session that never connected has nothing to report.
        if connection != nil {
            log.notice("cancelled")
        }
        complete(.failure(CancellationError()))
    }

    /// Returns whether the receive loop should keep going.
    private func handle(_ message: WebSocketMessage) -> Bool {
        guard outcome == nil else { return false }
        let payload: Data
        switch message {
        case let .text(text): payload = Data(text.utf8)
        case let .data(data): payload = data
        }
        guard let event = try? STTServerEvent.decode(payload) else {
            log.error("event: a message that could not be read, bytes=\(payload.count)")
            return true
        }

        // Event types, sizes and timings only. The text of an event is never logged.
        switch event {
        case .created:
            log.notice("event: transcript.created \(self.millisecondsSinceConnect) ms after connecting; sending audio")
            startSending()
        case let .partial(partial):
            partialCount += 1
            // The finals are what the transcript is built from, and there are few of them, so
            // they are written at a level macOS keeps: why a dictation came back empty is asked
            // long after the hold. The results that may still change come many to a second.
            if partial.isFinal { finalCount += 1 }
            log.log(level: partial.isFinal ? .default : .info, "event: transcript.partial is_final=\(partial.isFinal) chars=\(partial.text.count) audio=\(partial.range.lowerBound, format: .fixed(precision: 2))-\(partial.range.upperBound, format: .fixed(precision: 2)) s")
            assembler.apply(partial)
        case let .done(done):
            // The closing event's own text is often empty when the finals already carried the
            // words, so its count alone reads as "no transcript" when there was one.
            let text = assembler.finish(with: done)
            log.notice("event: transcript.done with chars=\(done.text.count) of its own, after partials=\(self.partialCount) finals=\(self.finalCount); assembled chars=\(text.count)")
            complete(.success(TranscriptionResult(text: text, isComplete: true)))
        case let .error(message):
            log.error("event: error (message withheld, chars=\(message.count))")
            complete(.failure(XAIError.transcription(message: message)))
        case let .unknown(type):
            log.notice("event: unknown type \(String(type.prefix(48)), privacy: .public)")
        }
        return outcome == nil
    }

    /// Audio queued before `transcript.created` waits in `outgoing` and goes out here, in order.
    private func startSending() {
        guard sendTask == nil, let connection else { return }
        let outgoing = outgoing
        sendTask = Task { [weak self] in
            for await message in outgoing {
                do {
                    try await connection.send(message)
                } catch {
                    await self?.connectionFailed(error)
                    return
                }
            }
        }
    }

    private var millisecondsSinceConnect: Int {
        connectedAt.map(VoicedLog.milliseconds(since:)) ?? 0
    }

    private func connectionFailed(_ error: any Error) {
        guard outcome == nil else { return }
        let nsError = error as NSError
        log.error("connection failed \(self.millisecondsSinceConnect) ms after connecting: handshake status=\(self.connection?.handshakeStatus ?? 0) close code=\(self.connection?.closeCode ?? 0) error=\(nsError.domain, privacy: .public) code=\(nsError.code)")
        switch connection?.handshakeStatus {
        case 401, 403:
            complete(.failure(XAIError.invalidAPIKey))
        case 429:
            complete(.failure(XAIError.rateLimited))
        case let status? where (400..<500).contains(status):
            complete(.failure(XAIError.connectionRefused(status: status)))
        case let status? where status >= 500:
            complete(.failure(XAIError.server(status: status, message: nil)))
        default:
            complete(.failure(XAIError.network(description: error.localizedDescription)))
        }
    }

    private func timedOut() {
        guard outcome == nil else { return }
        let text = assembler.text
        log.error("no transcript.done within the time limit; partials=\(self.partialCount) finals=\(self.finalCount) chars so far=\(text.count)")
        if text.isEmpty {
            complete(.failure(XAIError.timedOut))
        } else {
            complete(.success(TranscriptionResult(text: text, isComplete: false)))
        }
    }

    private func complete(_ result: Result<TranscriptionResult, any Error>) {
        guard outcome == nil else { return }
        outcome = result
        outgoingContinuation.finish()
        timeoutTask?.cancel()
        sendTask?.cancel()
        receiveTask?.cancel()
        if let connection {
            let summary = switch result {
            case let .success(transcript): "transcript chars=\(transcript.text.count) complete=\(transcript.isComplete)"
            case let .failure(error): VoicedLog.describe(error)
            }
            log.notice("closing the connection \(self.millisecondsSinceConnect) ms after connecting: \(summary, privacy: .public)")
            connection.close()
        }
        if let waiter {
            self.waiter = nil
            waiter.resume(with: result)
        }
    }
}
