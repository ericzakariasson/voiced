import AVFoundation
import Testing
@testable import VoicedKit

@Suite struct AudioChunkerTests {
    @Test func emitsFixedSizeChunksAndKeepsTheRemainder() {
        var chunker = AudioChunker(chunkByteCount: 4)

        #expect(chunker.append(Data([1, 2, 3])) == [])
        #expect(chunker.append(Data([4, 5, 6, 7, 8, 9])) == [Data([1, 2, 3, 4]), Data([5, 6, 7, 8])])
        #expect(chunker.flush() == Data([9]))
        #expect(chunker.flush() == nil)
    }

    @Test func preservesEveryByteInOrder() {
        var chunker = AudioChunker(chunkByteCount: 3200)
        let input = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0) })
        var output = Data()

        for start in stride(from: 0, to: input.count, by: 1234) {
            let piece = input[start..<min(start + 1234, input.count)]
            for chunk in chunker.append(Data(piece)) {
                #expect(chunk.count == 3200)
                output.append(chunk)
            }
        }
        output.append(chunker.flush() ?? Data())

        #expect(output == input)
    }

    @Test func defaultChunkIsOneHundredMilliseconds() {
        #expect(XAIConfiguration.default.chunkByteCount == 3200)
    }
}

@Suite struct PCM16ConverterTests {
    private func sineBuffer(sampleRate: Double, channels: AVAudioChannelCount, seconds: Double, amplitude: Float) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try #require(buffer.floatChannelData)
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) {
                data[channel][frame] = amplitude * sin(2 * .pi * 440 * Float(frame) / Float(sampleRate))
            }
        }
        return buffer
    }

    /// The pitch of a tone in 16 kHz PCM, from how often it crosses zero going up. A tone
    /// converted from the wrong rate keeps its samples and loses its pitch.
    private func pitch(of pcm: Data, sampleRate: Double = 16_000) -> Double {
        let samples = pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        guard samples.count > 1 else { return 0 }
        var risingCrossings = 0
        for index in 1..<samples.count where samples[index - 1] < 0 && samples[index] >= 0 {
            risingCrossings += 1
        }
        return Double(risingCrossings) / (Double(samples.count) / sampleRate)
    }

    @Test func theConverterIsBuiltFromTheFirstBuffersOwnFormat() throws {
        let converter = try #require(PCM16Converter(sampleRate: 16_000))
        #expect(converter.inputFormat == nil)

        var pcm = Data()
        for _ in 0..<10 {
            // A new format object each time, as equal as two can be.
            pcm.append(converter.convert(try sineBuffer(sampleRate: 24_000, channels: 1, seconds: 0.1, amplitude: 0.5)))
        }
        pcm.append(converter.finish())

        #expect(converter.inputFormat?.sampleRate == 24_000)
        #expect(converter.formatChanges == 0)
        #expect(converter.unconvertibleBuffers == 0)
        // One second in, one second out, at the pitch it went in.
        #expect(abs(pcm.count / 2 - 16_000) < 32)
        #expect(abs(pitch(of: pcm) - 440) < 5)
    }

    @Test func aBufferAtAnotherRateRebuildsTheConverterAndKeepsTheSpeed() throws {
        let converter = try #require(PCM16Converter(sampleRate: 16_000))

        // Half a second at 24 kHz, then the device moves to 48 kHz.
        var before = Data()
        for _ in 0..<5 {
            before.append(converter.convert(try sineBuffer(sampleRate: 24_000, channels: 1, seconds: 0.1, amplitude: 0.5)))
        }
        var after = Data()
        for _ in 0..<5 {
            after.append(converter.convert(try sineBuffer(sampleRate: 48_000, channels: 1, seconds: 0.1, amplitude: 0.5)))
        }
        after.append(converter.finish())

        #expect(converter.formatChanges == 1)
        #expect(converter.inputFormat?.sampleRate == 48_000)
        // Nothing was lost at the change: what the first converter held came out with the next buffer.
        #expect(abs((before.count + after.count) / 2 - 16_000) < 64)
        // Read at the old rate, the second half would last a second and sound an octave lower.
        #expect(abs(after.count / 2 - 8_000) < 400)
        #expect(abs(pitch(of: before) - 440) < 8)
        #expect(abs(pitch(of: Data(after.suffix(12_000))) - 440) < 8)
    }

    @Test func aChangeInTheNumberOfChannelsRebuildsTheConverter() throws {
        let converter = try #require(PCM16Converter(sampleRate: 16_000))

        var pcm = Data()
        for channels: AVAudioChannelCount in [1, 1, 2, 2, 1] {
            pcm.append(converter.convert(try sineBuffer(sampleRate: 48_000, channels: channels, seconds: 0.2, amplitude: 0.5)))
        }
        pcm.append(converter.finish())

        #expect(converter.formatChanges == 2)
        #expect(abs(pcm.count / 2 - 16_000) < 96)
        #expect(abs(pitch(of: pcm) - 440) < 8)
    }

    @Test func formatsAreComparedByTheAudioTheyDescribe() throws {
        let mono48 = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let sameAgain = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let mono24 = try #require(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        let stereo48 = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let integers48 = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: true))

        #expect(PCM16Converter.isSameAudio(mono48, sameAgain))
        #expect(!PCM16Converter.isSameAudio(mono48, mono24))
        #expect(!PCM16Converter.isSameAudio(mono48, stereo48))
        #expect(!PCM16Converter.isSameAudio(mono48, integers48))
    }

    @Test func buffersAreCountedAgainstTheClock() {
        let start = ContinuousClock.now

        // Ten buffers of a tenth of a second at 48 kHz, on time.
        var onTime = BufferTally()
        for index in 0..<10 {
            onTime.add(frames: 4_800, at: start + .milliseconds(100 * index))
        }
        #expect(onTime.buffers == 10)
        #expect(onTime.frames == 48_000)
        #expect(onTime.span == .milliseconds(900))
        #expect(onTime.measuredFramesPerSecond == 48_000)

        // Buffers that claim 24 kHz and come twice as often as that allows: really 48 kHz.
        var mislabelled = BufferTally()
        for index in 0..<20 {
            mislabelled.add(frames: 2_400, at: start + .milliseconds(50 * index))
        }
        #expect(mislabelled.measuredFramesPerSecond == 48_000)

        var one = BufferTally()
        #expect(one.measuredFramesPerSecond == nil)
        #expect(one.span == .zero)
        one.add(frames: 4_800, at: start)
        #expect(one.measuredFramesPerSecond == nil)
    }

    @Test func resamplesStereoFloatToMono16kHz() throws {
        let buffer = try sineBuffer(sampleRate: 48_000, channels: 2, seconds: 0.5, amplitude: 0.5)
        let converter = try #require(PCM16Converter(sampleRate: 16_000))

        var pcm = Data()
        for _ in 0..<4 {
            pcm.append(converter.convert(buffer))
        }
        // The resampler holds some audio back between calls; finish() must hand it over.
        let heldBack = 32_000 - pcm.count / 2
        #expect(heldBack > 0)
        pcm.append(converter.finish())

        // Two seconds in, two seconds out.
        #expect(abs(pcm.count / 2 - 32_000) < 32)
        #expect(converter.outputFormat.sampleRate == 16_000)
        #expect(converter.outputFormat.channelCount == 1)
        // A sine at half scale has an RMS of about -9 dBFS.
        #expect(abs(AudioLevel.decibels(pcm16: pcm) - -9.0) < 0.5)
    }

    @Test func passesThroughAudioAlreadyAtTheTargetRate() throws {
        let buffer = try sineBuffer(sampleRate: 16_000, channels: 1, seconds: 0.1, amplitude: 0.25)
        let converter = try #require(PCM16Converter(sampleRate: 16_000))

        #expect(converter.convert(buffer).count == 3200)
        #expect(converter.finish().isEmpty)
    }

    @Test func aCopyOfTheSamplesRebuildsTheSameBuffer() throws {
        let original = try sineBuffer(sampleRate: 48_000, channels: 2, seconds: 0.1, amplitude: 0.5)

        let samples = PCMSamples(copying: original)
        let rebuilt = try #require(samples.makeBuffer(format: original.format))

        #expect(samples.planes.count == 2)
        #expect(rebuilt.frameLength == original.frameLength)
        #expect(rebuilt.format == original.format)
        let originalData = try #require(original.floatChannelData)
        let rebuiltData = try #require(rebuilt.floatChannelData)
        for channel in 0..<2 {
            let byteCount = Int(original.frameLength) * MemoryLayout<Float>.size
            #expect(memcmp(originalData[channel], rebuiltData[channel], byteCount) == 0)
        }
    }

    @Test func aCopyOfInterleavedSamplesRebuildsTheSameBuffer() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2, interleaved: true))
        let original = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 441))
        original.frameLength = 441
        let originalData = try #require(original.int16ChannelData)
        for index in 0..<882 {
            originalData[0][index] = Int16(truncatingIfNeeded: index &* 37)
        }

        let samples = PCMSamples(copying: original)
        let rebuilt = try #require(samples.makeBuffer(format: format))

        #expect(samples.planes.map(\.count) == [882 * 2])
        let rebuiltData = try #require(rebuilt.int16ChannelData)
        #expect(memcmp(originalData[0], rebuiltData[0], 882 * 2) == 0)
    }

    @Test func aBufferShorterThanItsCapacityIsCopiedByLength() throws {
        let original = try sineBuffer(sampleRate: 48_000, channels: 1, seconds: 0.1, amplitude: 0.5)
        original.frameLength = 1000

        let samples = PCMSamples(copying: original)

        #expect(samples.frameLength == 1000)
        #expect(samples.planes.map(\.count) == [1000 * MemoryLayout<Float>.size])
        #expect(samples.makeBuffer(format: original.format)?.frameLength == 1000)
    }

    @Test func rejectsAFormatWithNoChannels() throws {
        // What `AVAudioEngine.inputNode` reports on a machine with no input device.
        let format = AVAudioFormat()
        let converter = try #require(PCM16Converter(sampleRate: 16_000))
        #expect(!converter.canConvert(format))
        #expect(converter.canConvert(try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))))
        // With nothing converted there is nothing held back either.
        #expect(converter.finish().isEmpty)
    }
}

@Suite struct AudioLevelTests {
    private func pcm(_ samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    @Test func silenceIsTheBottomOfTheScale() {
        #expect(AudioLevel.decibels(pcm16: pcm(Array(repeating: 0, count: 1600))) == AudioLevel.silence)
        #expect(AudioLevel.decibels(pcm16: Data()) == AudioLevel.silence)
    }

    @Test func fullScaleIsZeroDecibels() {
        #expect(AudioLevel.decibels(pcm16: pcm(Array(repeating: Int16.max, count: 1600))) == 0)
    }

    @Test func halvingTheAmplitudeDropsSixDecibels() {
        let loud = AudioLevel.decibels(pcm16: pcm(Array(repeating: 8000, count: 1600)))
        let soft = AudioLevel.decibels(pcm16: pcm(Array(repeating: 4000, count: 1600)))
        #expect(abs((loud - soft) - 6.02) < 0.01)
    }

    @Test func syntheticAudioHasTheLoudnessItWasAskedFor() {
        for target in [-62.0, -38.0, -28.0, -12.0] {
            #expect(abs(AudioLevel.decibels(pcm16: SyntheticAudio.noise(decibels: target, seconds: 0.1)) - target) < 0.5)
        }
    }
}
