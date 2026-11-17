import Foundation
import Testing
@testable import VoicedKit

/// Runs against the real login keychain under a throwaway service name, and never shows a prompt.
@Suite struct KeychainSecretStoreTests {
    private func makeStore() -> KeychainSecretStore {
        KeychainSecretStore(
            service: "com.ericzakariasson.Voiced.tests.\(UUID().uuidString)",
            account: "secret",
            allowsUserInteraction: false
        )
    }

    @Test func savesReadsUpdatesAndDeletes() throws {
        let store = makeStore()
        defer { try? store.delete() }

        #expect(try store.read() == nil)

        try store.save("first-value")
        #expect(try store.read() == "first-value")

        try store.save("second-value")
        #expect(try store.read() == "second-value")

        try store.delete()
        #expect(try store.read() == nil)
    }

    @Test func deletingAMissingSecretIsNotAnError() throws {
        try makeStore().delete()
    }

    @Test func storesAreIsolatedByServiceAndAccount() throws {
        let first = makeStore()
        let second = makeStore()
        defer {
            try? first.delete()
            try? second.delete()
        }

        try first.save("one")

        #expect(try second.read() == nil)
    }
}
