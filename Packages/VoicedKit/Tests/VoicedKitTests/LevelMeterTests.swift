import Foundation
import Testing
@testable import VoicedKit

@Suite struct LevelMeterTests {
    /// Runs audio through a fresh meter, 100 ms at a time, and returns the level shown for each chunk.
    private func levels(_ audio: Data, meter: inout LevelMeter) -> [Float] {
        SyntheticAudio.chunks(audio).map { meter.level(forPCM16: $0) }
    }

    private func levels(_ audio: Data) -> [Float] {
        var meter = LevelMeter()
        return levels(audio, meter: &meter)
    }

    /// The upper quartile and the lower quartile of the levels shown while something was audible.
    private func quartiles(_ shown: [Float]) -> (lower: Float, upper: Float) {
        let audible = shown.filter { $0 > 0 }.sorted()
        return (audible[audible.count / 4], audible[audible.count * 3 / 4])
    }

    /// From ordinary speech up to someone leaning into the microphone. A laptop microphone at
    /// arm's length gives peaks of about -35 to -25 dBFS.
    @Test(arguments: [-34.0, -28.0, -22.0, -12.0])
    func speechAtAnyOrdinaryVolumeReachesTheTopAndMovesBelowIt(decibels: Double) {
        var meter = LevelMeter()
        let shown = levels(SyntheticAudio.speech(decibels: decibels, seconds: 20), meter: &meter)
        let statistics = meter.statistics

        // The loud syllables fill the meter, in every second from the first.
        #expect(statistics.highestShown == 1)
        #expect(statistics.ninetiethPercentileShown >= 0.95)
        for second in 0..<20 {
            #expect(shown[second * 10..<(second + 1) * 10].max()! >= 0.8, "second \(second) at \(decibels) dBFS")
        }
        // The quieter ones do not: the typical level sits well below the top, and the levels spread out.
        #expect(statistics.medianShown >= 0.55 && statistics.medianShown <= 0.85)
        let (lower, upper) = quartiles(shown)
        #expect(upper - lower >= 0.3)
    }

    @Test func softSpeechStillReachesTheTop() {
        var meter = LevelMeter()
        _ = levels(SyntheticAudio.speech(decibels: -40, seconds: 20), meter: &meter)

        #expect(meter.statistics.highestShown == 1)
        #expect(meter.statistics.medianShown >= 0.4)
    }

    @Test func aWhisperInAQuietRoomStillMovesTheMeter() {
        var meter = LevelMeter()
        _ = levels(SyntheticAudio.speech(decibels: -48, room: -70, seconds: 10), meter: &meter)

        #expect(meter.statistics.audibleChunks > 30)
        #expect(meter.statistics.ninetiethPercentileShown >= 0.4)
    }

    @Test func theFixedScaleItReplacesLeftTheSameSpeechInTheBottomHalf() {
        // The first meter mapped -50...0 dBFS straight onto 0...1.
        let chunks = SyntheticAudio.chunks(SyntheticAudio.speech(decibels: -30, seconds: 10))
        let old = chunks.map { min(1, max(0, (AudioLevel.decibels(pcm16: $0) + 50) / 50)) }

        #expect(old.max()! < 0.45)
        #expect(levels(SyntheticAudio.speech(decibels: -30, seconds: 10)).max()! >= 0.99)
    }

    @Test func digitalSilenceIsFlat() {
        #expect(levels(Data(count: 32_000 * 5)).allSatisfy { $0 == 0 })
    }

    @Test(arguments: [-75.0, -62.0, -52.0, -44.0])
    func aSteadyRoomIsFlatHoweverLoudItIs(decibels: Double) {
        #expect(levels(SyntheticAudio.noise(decibels: decibels, seconds: 12)).allSatisfy { $0 == 0 })
    }

    @Test func theMeterFallsFlatTheMomentSpeechStops() {
        var meter = LevelMeter()
        _ = levels(SyntheticAudio.speech(decibels: -28, seconds: 5), meter: &meter)
        let afterwards = levels(SyntheticAudio.noise(decibels: -62, seconds: 5, seed: 3), meter: &meter)

        #expect(afterwards.allSatisfy { $0 == 0 })
    }

    @Test func pausesBetweenPhrasesReadAsZero() {
        let shown = levels(SyntheticAudio.speech(decibels: -28, seconds: 10))
        // The synthetic speech pauses for 400 ms after every six syllables, so some chunks hold only the room.
        #expect(shown.filter { $0 == 0 }.count >= 10)
    }

    @Test func speechOverANoisyRoomStillFillsTheMeterAndThePausesStayFlat() {
        var meter = LevelMeter()
        let shown = levels(SyntheticAudio.speech(decibels: -26, room: -48, seconds: 10), meter: &meter)

        #expect(meter.statistics.ninetiethPercentileShown >= 0.9)
        #expect(shown.filter { $0 == 0 }.count >= 10)
    }

    @Test func aCoughDoesNotShrinkTheSpeechAfterIt() {
        var meter = LevelMeter()
        _ = levels(SyntheticAudio.speech(decibels: -30, seconds: 4), meter: &meter)
        _ = meter.level(forPCM16: SyntheticAudio.noise(decibels: -6, seconds: 0.1))
        let afterwards = levels(SyntheticAudio.speech(decibels: -30, seconds: 6, seed: 11), meter: &meter)

        // Reduced at first, and back to the top within three seconds.
        #expect(afterwards[0..<10].max()! >= 0.5)
        #expect(afterwards[20..<60].max()! >= 0.9)
    }

    @Test func followsASpeakerWhoGetsQuieter() {
        var meter = LevelMeter()
        _ = levels(SyntheticAudio.speech(decibels: -14, seconds: 4), meter: &meter)
        let quieter = levels(SyntheticAudio.speech(decibels: -34, seconds: 10, seed: 11), meter: &meter)

        #expect(quieter[60..<100].max()! >= 0.9)
    }

    @Test func followsASpeakerWhoGetsLouderAtOnce() {
        var meter = LevelMeter()
        _ = levels(SyntheticAudio.speech(decibels: -36, seconds: 4), meter: &meter)
        let louder = levels(SyntheticAudio.speech(decibels: -16, seconds: 2, seed: 11), meter: &meter)

        #expect(louder[0..<5].max()! >= 0.99)
    }

    @Test func speechThatStartsWithTheRecordingShowsAtOnceAndFillsTheMeterAfterTheFirstPause() {
        // No room noise first, so the meter cannot tell the room from the speaker until a pause.
        let shown = levels(SyntheticAudio.speech(decibels: -28, seconds: 4, leadIn: 0))

        #expect(shown[0..<10].max()! >= 0.5)
        #expect(shown[20..<40].max()! >= 0.99)
    }

    @Test func levelsStayBetweenZeroAndOne() {
        var meter = LevelMeter()
        let inputs: [Double] = [-120, -100, -80, -50, -30, -10, 0, 6, -200, -3, -60]
        for decibels in inputs {
            let level = meter.level(forDecibels: decibels, seconds: 0.1)
            #expect(level >= 0 && level <= 1)
        }
    }

    @Test func anEmptyChunkShowsNothingAndIsNotCounted() {
        var meter = LevelMeter()

        #expect(meter.level(forPCM16: Data()) == 0)
        #expect(meter.statistics == LevelMeter.Statistics())
    }

    @Test func chunksOfDigitalSilenceAreCountedAndThoseThatLeadAreTimed() {
        var meter = LevelMeter()
        let silence = Data(count: 3200)
        // A device that hands over zeros for 300 ms before it is really recording, mutes
        // itself once in the middle, and ends on a short silent tail.
        let chunks = [silence, silence, silence]
            + SyntheticAudio.chunks(SyntheticAudio.speech(decibels: -28, seconds: 1))
            + [silence]
            + SyntheticAudio.chunks(SyntheticAudio.speech(decibels: -28, seconds: 1))
            + [Data(count: 1600)]
        for chunk in chunks {
            _ = meter.level(forPCM16: chunk)
        }
        let statistics = meter.statistics

        #expect(statistics.chunks == 25)
        #expect(statistics.silentChunks == 5)
        #expect(statistics.leadingSilentChunks == 3)
        #expect(abs(statistics.leadingSilentSeconds - 0.3) < 0.001)
        #expect(statistics.quietestInput == AudioLevel.silence)
    }

    @Test func aRecordingOfNothingButSilenceIsAllLeadingSilence() {
        var meter = LevelMeter()
        for _ in 0..<4 {
            _ = meter.level(forPCM16: Data(count: 3200))
        }

        #expect(meter.statistics.silentChunks == 4)
        #expect(meter.statistics.leadingSilentChunks == 4)
        #expect(abs(meter.statistics.leadingSilentSeconds - 0.4) < 0.001)
    }

    @Test func aMicrophoneInAQuietRoomGivesNoSilentChunks() {
        var meter = LevelMeter()
        _ = levels(SyntheticAudio.speech(decibels: -28, seconds: 3), meter: &meter)

        #expect(meter.statistics.silentChunks == 0)
        #expect(meter.statistics.leadingSilentChunks == 0)
        #expect(meter.statistics.leadingSilentSeconds == 0)
    }

    @Test func theNinetiethPercentileTellsOneBumpFromSoundThatWentOn() {
        // Forty chunks of a quiet room with one loud bump among them.
        var bump = LevelMeter()
        for index in 0..<40 {
            _ = bump.level(forDecibels: index == 20 ? -30 : -60, seconds: 0.1)
        }
        #expect(bump.statistics.loudestInput == -30)
        #expect(bump.statistics.ninetiethPercentileInput == -60)

        // The same room with someone speaking through a quarter of it.
        var speech = LevelMeter()
        for index in 0..<40 {
            _ = speech.level(forDecibels: index % 4 == 0 ? -30 : -60, seconds: 0.1)
        }
        #expect(speech.statistics.loudestInput == -30)
        #expect(speech.statistics.ninetiethPercentileInput == -30)
        #expect(speech.statistics.medianInput == -60)
    }

    @Test func statisticsDescribeTheDictationInNumbers() {
        var meter = LevelMeter()
        _ = levels(SyntheticAudio.speech(decibels: -28, seconds: 6), meter: &meter)
        let statistics = meter.statistics

        #expect(statistics.chunks == 60)
        #expect(statistics.audibleChunks > 30 && statistics.audibleChunks < 60)
        #expect(abs(statistics.quietestInput - -62) < 2)
        #expect(statistics.loudestInput > -32 && statistics.loudestInput <= -27)
        #expect(statistics.medianInput > statistics.quietestInput && statistics.medianInput < statistics.loudestInput)
        #expect(abs(statistics.floor - -62) < 2)
        #expect(statistics.ceiling > -36 && statistics.ceiling < -26)
        #expect(statistics.highestShown == 1)
    }
}
