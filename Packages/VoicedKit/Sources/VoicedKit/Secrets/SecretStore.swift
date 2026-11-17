import Foundation
import LocalAuthentication
import Security

public protocol SecretStore: Sendable {
    func read() throws -> String?
    func save(_ secret: String) throws
    func delete() throws
}

public struct KeychainError: Error, Equatable, LocalizedError, Sendable {
    public var status: OSStatus

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
        return "Keychain: \(message)"
    }
}

/// Stores one secret as a generic password in the user's login keychain.
public struct KeychainSecretStore: SecretStore {
    public static let defaultService = "com.ericzakariasson.Voiced"
    public static let apiKeyAccount = "xai-api-key"

    private let service: String
    private let account: String
    private let allowsUserInteraction: Bool

    /// - Parameter allowsUserInteraction: Pass `false` to fail instead of showing a keychain prompt.
    public init(
        service: String = KeychainSecretStore.defaultService,
        account: String = KeychainSecretStore.apiKeyAccount,
        allowsUserInteraction: Bool = true
    ) {
        self.service = service
        self.account = account
        self.allowsUserInteraction = allowsUserInteraction
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if !allowsUserInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    public func save(_ secret: String) throws {
        let data = Data(secret.utf8)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "Voiced Grok API Key"
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: updateStatus)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
