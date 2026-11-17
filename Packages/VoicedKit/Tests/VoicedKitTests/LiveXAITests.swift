import AVFoundation
import Foundation
import Testing
@testable import VoicedKit

private enum LiveEnvironment {
    static var apiKey: String? {
        let key = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        return key.isEmpty ? nil : key
    }

    static var networkTestsEnabled: Bool {
        apiKey != nil || ProcessInfo.processInfo.environment["VOICED_LIVE_TESTS"] == "1"
    }
}

/// Runs the whole pipeline against the real xAI API. Skipped unless `XAI_API_KEY` is set:
///
///     XAI_API_KEY=... make test-live
///
/// The key is read from the environment only and never printed.
@Suite(.enabled(if: LiveEnvironment.apiKey != nil, "XAI_API_KEY is not set"))
struct LiveXAITests {

    private static let spokenText = "Um, so I think we should, uh, ship the new build on Friday. No wait, on Monday."

    /// Speech from `say`, converted the same way the app converts microphone audio.
    private func synthesizedSpeech() throws -> Data {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("voiced-live-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: file) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", file.path, Self.spokenText]
        try say.run()
        say.waitUntilExit()
        try #require(say.terminationStatus == 0)

        let audioFile = try AVAudioFile(forReading: file)
        let format = audioFile.processingFormat
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioFile.length)))
        try audioFile.read(into: buffer)
        let converter = try #require(PCM16Converter(sampleRate: 16_000))
        return converter.convert(buffer)
    }

    @Test(.timeLimit(.minutes(2)))
    func transcribesAndCleansSynthesizedSpeech() async throws {
        let apiKey = try #require(LiveEnvironment.apiKey)
        let audio = try synthesizedSpeech()
        try #require(audio.count > 32_000)

        let session = StreamingTranscriptionSession(apiKey: apiKey)
        await session.start()
        let chunkSize = XAIConfiguration.default.chunkByteCount
        var offset = 0
        while offset < audio.count {
            let end = min(offset + chunkSize, audio.count)
            await session.send(audio: audio.subdata(in: offset..<end))
            offset = end
            // Real-time pacing, as the docs ask for and as a microphone would deliver it.
            try await Task.sleep(for: .milliseconds(100))
        }

        let released = ContinuousClock.now
        let transcription = try await session.finish()
        let transcribed = ContinuousClock.now
        print("Transcript (\(transcribed - released) after end of audio, complete: \(transcription.isComplete)): \(transcription.text)")
        #expect(transcription.isComplete)
        #expect(transcription.text.localizedCaseInsensitiveContains("build"))

        let cleaned = try await TranscriptCleaner(apiKey: apiKey).clean(transcription.text)
        print("Cleaned (\(ContinuousClock.now - transcribed)): \(cleaned)")
        let accepted = try #require(CleanupGuard.accept(cleaned: cleaned, raw: transcription.text))
        #expect(accepted.localizedCaseInsensitiveContains("Monday"))
        #expect(!accepted.localizedCaseInsensitiveContains("um,"))
    }

    @Test(.timeLimit(.minutes(1)))
    func theKeyPassesTheSettingsCheck() async throws {
        let apiKey = try #require(LiveEnvironment.apiKey)
        try await APIKeyChecker().check(apiKey)
    }
}

/// Checks how the real API turns away a made-up key. Needs the network but no key:
///
///     VOICED_LIVE_TESTS=1 make test-live
@Suite(.enabled(if: LiveEnvironment.networkTestsEnabled, "set VOICED_LIVE_TESTS=1 or XAI_API_KEY"))
struct LiveXAIRejectionTests {
    private let madeUpKey = "xai-not-a-real-key"

    @Test(.timeLimit(.minutes(1)))
    func theStreamingEndpointRefusesAMadeUpKey() async throws {
        let session = StreamingTranscriptionSession(apiKey: madeUpKey, finishTimeout: .seconds(20))
        await session.start()

        await #expect(throws: XAIError.connectionRefused(status: 400)) {
            try await session.finish()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func theResponsesEndpointRejectsAMadeUpKey() async throws {
        await #expect(throws: XAIError.invalidAPIKey) {
            try await TranscriptCleaner(apiKey: madeUpKey).clean("hello")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func theKeyCheckRejectsAMadeUpKey() async throws {
        await #expect(throws: XAIError.invalidAPIKey) {
            try await APIKeyChecker().check(madeUpKey)
        }
    }
}
