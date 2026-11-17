import Foundation
import Testing
@testable import VoicedKit

/// The log must never carry text that came from the server: an error message can quote the key
/// or what was dictated.
@Suite struct LoggingTests {
    private let secret = "xai-not-a-real-key and the words that were dictated"

    @Test func serverMessagesAreWithheldFromErrorDescriptions() {
        let errors: [XAIError] = [
            .server(status: 400, message: secret),
            .transcription(message: secret),
            .network(description: secret),
        ]

        for error in errors {
            let described = VoicedLog.describe(error)
            #expect(!described.contains("xai-not-a-real-key"))
            #expect(!described.contains("dictated"))
        }
    }

    @Test func errorDescriptionsKeepTheKindAndTheStatus() {
        #expect(VoicedLog.describe(XAIError.server(status: 503, message: nil)) == "xai.server status=503")
        #expect(VoicedLog.describe(XAIError.server(status: 400, message: "x")) == "xai.server status=400 (message withheld)")
        #expect(VoicedLog.describe(XAIError.connectionRefused(status: 400)) == "xai.connectionRefused status=400")
        #expect(VoicedLog.describe(XAIError.invalidAPIKey) == "xai.invalidAPIKey")
        #expect(VoicedLog.describe(XAIError.timedOut) == "xai.timedOut")
        #expect(VoicedLog.describe(AudioCaptureError.noInputDevice) == "capture.noInputDevice")
        #expect(VoicedLog.describe(TextInsertionError.accessibilityNotGranted) == "insertion.accessibilityNotGranted")
        #expect(VoicedLog.describe(KeychainError(status: -25300)) == "keychain status=-25300")
        #expect(VoicedLog.describe(CancellationError()) == "cancelled")
        #expect(VoicedLog.describe(URLError(.notConnectedToInternet)) == "NSURLErrorDomain code=-1009")
    }

    @Test func onlyAnIdentifierIsTakenFromAnErrorBody() {
        let body = Data(#"{"code": "invalid-argument", "error": "Incorrect API key provided: xai-not-a-real-key"}"#.utf8)
        #expect(VoicedLog.errorCode(inBody: body) == "invalid-argument")

        let nested = Data(#"{"error": {"code": "rate_limit.exceeded", "message": "slow down"}}"#.utf8)
        #expect(VoicedLog.errorCode(inBody: nested) == "rate_limit.exceeded")
    }

    @Test func anErrorCodeThatIsNotAnIdentifierIsDropped() {
        let sentence = Data(#"{"code": "the words that were dictated"}"#.utf8)
        let long = Data(#"{"code": "\#(String(repeating: "a", count: 41))"}"#.utf8)
        let number = Data(#"{"code": 400}"#.utf8)

        #expect(VoicedLog.errorCode(inBody: sentence) == "none")
        #expect(VoicedLog.errorCode(inBody: long) == "none")
        #expect(VoicedLog.errorCode(inBody: number) == "none")
        #expect(VoicedLog.errorCode(inBody: Data("not json".utf8)) == "none")
    }
}
