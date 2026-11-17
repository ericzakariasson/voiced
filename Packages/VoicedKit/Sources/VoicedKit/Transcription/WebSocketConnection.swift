import Foundation

public enum WebSocketMessage: Equatable, Sendable {
    case data(Data)
    case text(String)
}

public protocol WebSocketConnection: Sendable {
    func send(_ message: WebSocketMessage) async throws
    func receive() async throws -> WebSocketMessage
    func close()
    /// HTTP status of the upgrade response, once one has arrived.
    var handshakeStatus: Int? { get }
    /// The WebSocket close code, once the connection has been closed.
    var closeCode: Int? { get }
}

extension WebSocketConnection {
    public var closeCode: Int? { nil }
}

public protocol WebSocketConnecting: Sendable {
    /// Opens a connection. Failures surface from the first `send` or `receive`.
    func connect(_ request: URLRequest) -> any WebSocketConnection
}

public struct URLSessionWebSocketConnector: WebSocketConnecting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(_ request: URLRequest) -> any WebSocketConnection {
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionWebSocketConnection(task: task)
    }
}

struct URLSessionWebSocketConnection: WebSocketConnection {
    let task: URLSessionWebSocketTask

    func send(_ message: WebSocketMessage) async throws {
        switch message {
        case let .data(data):
            try await task.send(.data(data))
        case let .text(text):
            try await task.send(.string(text))
        }
    }

    func receive() async throws -> WebSocketMessage {
        switch try await task.receive() {
        case let .data(data):
            return .data(data)
        case let .string(text):
            return .text(text)
        @unknown default:
            throw XAIError.malformedResponse
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }

    var handshakeStatus: Int? {
        (task.response as? HTTPURLResponse)?.statusCode
    }

    var closeCode: Int? {
        task.closeCode == .invalid ? nil : task.closeCode.rawValue
    }
}
