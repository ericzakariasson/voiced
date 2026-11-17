import Foundation

/// Asks xAI whether an API key is usable, so a mistyped key is caught when it is saved.
public struct APIKeyChecker: Sendable {
    private let configuration: XAIConfiguration
    private let transport: any HTTPTransport

    public init(configuration: XAIConfiguration = .default, transport: any HTTPTransport = URLSession.shared) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Throws `XAIError.invalidAPIKey` when xAI rejects the key or reports it blocked or disabled.
    public func check(_ apiKey: String) async throws {
        var request = URLRequest(url: configuration.apiKeyInfoURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as XAIError {
            throw error
        } catch {
            throw XAIError.network(description: error.localizedDescription)
        }
        guard response.statusCode == 200 else {
            throw XAIError.fromHTTP(status: response.statusCode, body: data)
        }
        if let info = try? JSONDecoder().decode(KeyInfo.self, from: data), info.isUnusable {
            throw XAIError.invalidAPIKey
        }
    }

    private struct KeyInfo: Decodable {
        var api_key_blocked: Bool?
        var api_key_disabled: Bool?
        var team_blocked: Bool?

        var isUnusable: Bool {
            api_key_blocked == true || api_key_disabled == true || team_blocked == true
        }
    }
}
