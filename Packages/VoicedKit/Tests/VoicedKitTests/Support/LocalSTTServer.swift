import Foundation
import Network

/// A WebSocket server on localhost that speaks the streaming speech-to-text protocol as the xAI
/// docs describe it. It lets the tests drive the real `URLSession` transport without the network.
final class LocalSTTServer: @unchecked Sendable {
    struct Recording: Sendable {
        var audioFrames: [Data] = []
        var textMessages: [String] = []
        /// Whether any audio arrived before the server announced it was ready.
        var audioArrivedBeforeReady = false
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalSTTServer")
    private let readyDelay: Duration
    private let transcript: String
    private var recording = Recording()
    private var isReady = false

    /// - Parameter readyDelay: How long the server waits before sending `transcript.created`.
    init(transcript: String, readyDelay: Duration = .milliseconds(150)) throws {
        self.transcript = transcript
        self.readyDelay = readyDelay

        let webSocketOptions = NWProtocolWebSocket.Options()
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
        listener = try NWListener.onLoopback(using: parameters)

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
    }

    /// Starts listening and returns the `ws://` URL of the endpoint.
    func start() async throws -> URL {
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port!)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return URL(string: "ws://127.0.0.1:\(port.rawValue)/v1/stt")!
    }

    func stop() {
        listener.cancel()
    }

    func snapshot() -> Recording {
        queue.sync { recording }
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            connection.stateUpdateHandler = nil
            queue.asyncAfter(deadline: .now() + readyDelay.timeInterval) {
                self.isReady = true
                self.send(#"{"type": "transcript.created", "id": "local-session"}"#, on: connection)
            }
            receive(on: connection)
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self, error == nil, let content else { return }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            switch metadata?.opcode {
            case .binary:
                if !isReady { recording.audioArrivedBeforeReady = true }
                recording.audioFrames.append(content)
            case .text:
                let text = String(decoding: content, as: UTF8.self)
                recording.textMessages.append(text)
                if text.contains("audio.done") {
                    finish(on: connection)
                    return
                }
            default:
                break
            }
            receive(on: connection)
        }
    }

    private func finish(on connection: NWConnection) {
        let seconds = Double(recording.audioFrames.reduce(0) { $0 + $1.count }) / 32_000
        let escaped = transcript.replacingOccurrences(of: "\"", with: "\\\"")
        send(#"{"type": "transcript.partial", "text": "\#(escaped)", "words": [{"text": "\#(escaped)", "start": 0.1, "end": \#(seconds)}], "is_final": true, "speech_final": true, "start": 0.0, "duration": \#(seconds)}"#, on: connection)
        send(#"{"type": "transcript.done", "text": "\#(escaped)", "words": [{"text": "\#(escaped)", "start": 0.1, "end": \#(seconds)}], "duration": \#(seconds)}"#, on: connection) {
            connection.cancel()
        }
    }

    private func send(_ text: String, on connection: NWConnection, then completion: (@Sendable () -> Void)? = nil) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { _ in
            completion?()
        })
    }
}

private extension NWListener {
    /// A listener on a free port of the loopback address and of no other. A test run then
    /// offers nothing to the network the Mac is on, and gives its firewall nothing to ask about.
    static func onLoopback(using parameters: NWParameters) throws -> NWListener {
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        return try NWListener(using: parameters)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

/// Accepts one TCP connection and returns the first bytes the client sends: for a WebSocket
/// client, the HTTP upgrade request.
final class RequestCapturingServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "RequestCapturingServer")
    private let (requests, requestContinuation) = AsyncStream<String>.makeStream()

    init() throws {
        listener = try NWListener.onLoopback(using: .tcp)
        listener.newConnectionHandler = { [queue, requestContinuation] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                requestContinuation.yield(String(decoding: data ?? Data(), as: UTF8.self))
                connection.cancel()
            }
        }
    }

    func start() async throws -> URL {
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port!)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return URL(string: "ws://127.0.0.1:\(port.rawValue)/v1/stt")!
    }

    func firstRequest() async -> String? {
        for await request in requests {
            return request
        }
        return nil
    }

    func stop() {
        listener.cancel()
        requestContinuation.finish()
    }
}
