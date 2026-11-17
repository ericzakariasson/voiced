import Foundation
import Testing
@testable import VoicedKit

struct WaitTimedOut: Error {}

/// Polls until `condition` holds, failing the test after `timeout`.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @MainActor () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw WaitTimedOut()
}

/// A scripted WebSocket: tests push server messages in and read what the client sent.
final class FakeWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var sentMessages: [WebSocketMessage] = []
    private var status: Int?
    private var closed = false
    private let incoming: AsyncThrowingStream<WebSocketMessage, any Error>
    private let incomingContinuation: AsyncThrowingStream<WebSocketMessage, any Error>.Continuation

    init() {
        (incoming, incomingContinuation) = AsyncThrowingStream.makeStream()
    }

    var sent: [WebSocketMessage] {
        lock.withLock { sentMessages }
    }

    var isClosed: Bool {
        lock.withLock { closed }
    }

    var handshakeStatus: Int? {
        lock.withLock { status }
    }

    func serverSends(_ json: String) {
        incomingContinuation.yield(.text(json))
    }

    func serverFails(_ error: any Error, handshakeStatus: Int? = nil) {
        lock.withLock { status = handshakeStatus }
        incomingContinuation.finish(throwing: error)
    }

    func send(_ message: WebSocketMessage) async throws {
        lock.withLock { sentMessages.append(message) }
    }

    func receive() async throws -> WebSocketMessage {
        for try await message in incoming {
            return message
        }
        throw URLError(.networkConnectionLost)
    }

    func close() {
        lock.withLock { closed = true }
        incomingContinuation.finish(throwing: URLError(.cancelled))
    }
}

final class FakeWebSocketConnector: WebSocketConnecting, @unchecked Sendable {
    let connection = FakeWebSocketConnection()
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func connect(_ request: URLRequest) -> any WebSocketConnection {
        lock.withLock { recordedRequests.append(request) }
        return connection
    }
}

/// Answers every request with one canned response and records what it was asked.
final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case response(status: Int, body: String)
        case failure(URLError)
    }

    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    private let reply: Reply

    init(_ reply: Reply) {
        self.reply = reply
    }

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recordedRequests.append(request) }
        switch reply {
        case let .response(status, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(body.utf8), response)
        case let .failure(error):
            throw error
        }
    }
}

/// Settings kept in memory and gone with the test: nothing is written into the settings of
/// whoever runs the tests. A saved on or off comes back as the number the preferences would
/// give back for it.
final class InMemorySettingsStore: SettingsStore {
    private(set) var values: [String: Any]

    init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func set(_ value: Bool, forKey defaultName: String) {
        values[defaultName] = NSNumber(value: value)
    }
}

func jsonObject(_ data: Data?) throws -> [String: Any] {
    let data = try #require(data)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
