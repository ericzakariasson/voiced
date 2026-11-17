import Foundation
import os

/// Loggers for each stage of a dictation. Watch them with:
///
///     /usr/bin/log stream --level info --style compact --predicate 'subsystem == "com.ericzakariasson.Voiced"'
///
/// What may be logged: stages, counts, sizes, durations, HTTP statuses and kinds of error.
///
/// What must never be logged: the API key, audio, transcript text, which keys were pressed, or a
/// message from the server, which can quote any of those. Values are logged as `public` so they
/// show in `log stream`; this rule is what makes that safe.
public enum VoicedLog {
    public static let subsystem = "com.ericzakariasson.Voiced"

    /// The event tap, and the hotkey going down and up.
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    /// The loop as a whole: one line per step of each dictation.
    public static let dictation = Logger(subsystem: subsystem, category: "dictation")
    /// The audio engine starting and stopping.
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    /// The streaming connection to xAI: connect, each event's type, and close.
    public static let transcription = Logger(subsystem: subsystem, category: "transcription")
    /// The cleanup request and the status of its response.
    public static let cleanup = Logger(subsystem: subsystem, category: "cleanup")
    /// The pasteboard and the paste keystroke.
    public static let insertion = Logger(subsystem: subsystem, category: "insertion")
    /// Launch, permissions, and saving the API key.
    public static let setup = Logger(subsystem: subsystem, category: "setup")

    /// A description of `error` that is safe to log: its kind and any status, never a message
    /// that came from the server.
    public static func describe(_ error: any Error) -> String {
        switch error {
        case let error as XAIError:
            return describe(error)
        case let error as AudioCaptureError:
            switch error {
            case .noInputDevice:
                return "capture.noInputDevice"
            case let .engineFailed(description):
                // Written by the audio system, about the audio device.
                return "capture.engineFailed (\(description))"
            }
        case let error as TextInsertionError:
            switch error {
            case .accessibilityNotGranted:
                return "insertion.accessibilityNotGranted"
            case .keystrokeUnavailable:
                return "insertion.keystrokeUnavailable"
            }
        case let error as KeychainError:
            return "keychain status=\(error.status)"
        case is CancellationError:
            return "cancelled"
        default:
            let error = error as NSError
            return "\(error.domain) code=\(error.code)"
        }
    }

    private static func describe(_ error: XAIError) -> String {
        switch error {
        case .invalidAPIKey:
            "xai.invalidAPIKey"
        case .rateLimited:
            "xai.rateLimited"
        case let .server(status, message):
            message == nil ? "xai.server status=\(status)" : "xai.server status=\(status) (message withheld)"
        case let .connectionRefused(status):
            "xai.connectionRefused status=\(status)"
        case .transcription:
            "xai.transcription (message withheld)"
        case .malformedResponse:
            "xai.malformedResponse"
        case .incompleteResponse:
            "xai.incompleteResponse"
        case .timedOut:
            "xai.timedOut"
        case .network:
            "xai.network"
        }
    }

    /// The `code` of an xAI error body, such as `invalid-argument`, when it looks like an
    /// identifier. The body's message is never returned: it can quote the key or the request.
    public static func errorCode(inBody body: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let code = object["code"] as? String ?? (object["error"] as? [String: Any])?["code"] as? String,
            !code.isEmpty, code.count <= 40,
            code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) })
        else {
            return "none"
        }
        return code
    }

    /// Whole milliseconds from `start` to now.
    public static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start) / .milliseconds(1))
    }
}
