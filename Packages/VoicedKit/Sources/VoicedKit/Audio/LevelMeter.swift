import Foundation

/// Turns the loudness of microphone audio into a 0...1 level for the recording indicator.
///
/// A fixed scale wastes most of a meter: speech into a laptop microphone sits around -40 to
/// -20 dBFS, a small slice of what 16 bits can hold. This meter works in decibels, which is how
/// loudness is heard, and fits its scale to what it has been hearing:
///
/// - The **floor** is the quietest stretch of the last few seconds, which is the room. Anything
///   within a few decibels of it reads as zero, so silence stays flat however noisy the room is.
/// - The **ceiling** follows the loudest recent speech up quickly and comes back down slowly, so
///   whatever volume the speaker settles at reaches the top of the meter on its loud syllables,
///   and the quieter ones in between show as less: the bars move with the voice.
///
/// One meter serves one dictation. Feed it every chunk in order.
public struct LevelMeter: Sendable {
    /// Numbers describing one dictation's levels, for the log. Nothing here can be turned back
    /// into audio.
    public struct Statistics: Equatable, Sendable {
        public var chunks = 0
        /// Chunks loud enough to move the meter.
        public var audibleChunks = 0
        /// Chunks of digital silence: every sample zero, which no live microphone gives. A
        /// device hands these over while it is not really recording yet, or is muted.
        public var silentChunks = 0
        /// How many of them came before the first chunk that held anything, and how long they
        /// lasted: time in which the recording was running and nothing could be heard.
        public var leadingSilentChunks = 0
        public var leadingSilentSeconds = 0.0
        public var quietestInput = 0.0
        public var medianInput = 0.0
        /// Near the loudest when sound went on through the dictation, near the median when
        /// the loudest was one bump.
        public var ninetiethPercentileInput = 0.0
        public var loudestInput = 0.0
        /// Where the scale's ends finished, in dBFS.
        public var floor = 0.0
        public var ceiling = 0.0
        /// The level shown, over the audible chunks only.
        public var medianShown: Float = 0
        public var ninetiethPercentileShown: Float = 0
        public var highestShown: Float = 0
    }

    /// The room is never taken to be louder than this, or quiet speech would count as room noise.
    static let highestFloor = -42.0
    static let lowestFloor = -80.0
    /// How far above the floor a sound must be before the meter moves.
    static let gate = 6.0
    /// The meter never spans less than this, so a sound just past the gate does not fill it.
    static let narrowestSpan = 12.0
    /// Nor more than this below the ceiling: quieter than that reads as zero.
    static let widestSpan = 30.0
    /// The ceiling does not follow a speaker quieter than this.
    static let lowestCeiling = -48.0
    static let highestCeiling = -3.0
    /// How much of the way the ceiling moves toward a louder chunk, and the most it may rise for
    /// one chunk, so a cough does not shrink everything after it.
    static let ceilingAttack = 0.8
    static let largestCeilingRise = 10.0
    /// Decibels per second the ceiling comes back down. Slow enough that the ceiling stays near
    /// the loud syllables and the quieter ones show as less than full height.
    static let ceilingRelease = 3.0
    /// How far back the floor looks.
    static let floorWindow = 3.0

    private static let sampleRate = 16_000.0

    private var recent: [(decibels: Double, seconds: Double)] = []
    /// Starts at the bottom, so the first thing said fills the meter whatever its volume.
    private var ceiling = LevelMeter.lowestCeiling
    private var inputs: [Double] = []
    private var shown: [Float] = []
    private var silentChunks = 0
    private var leadingSilentChunks = 0
    private var leadingSilentSeconds = 0.0

    public init() {}

    /// The level to show for the next chunk of mono 16-bit PCM at 16 kHz.
    public mutating func level(forPCM16 data: Data) -> Float {
        let samples = data.count / MemoryLayout<Int16>.size
        guard samples > 0 else { return 0 }
        return level(forDecibels: AudioLevel.decibels(pcm16: data), seconds: Double(samples) / Self.sampleRate)
    }

    /// The level to show for a chunk of the given loudness (RMS, in dBFS) and length.
    public mutating func level(forDecibels decibels: Double, seconds: Double) -> Float {
        let decibels = max(decibels, AudioLevel.silence)
        if decibels <= AudioLevel.silence {
            if silentChunks == inputs.count {
                leadingSilentChunks += 1
                leadingSilentSeconds += seconds
            }
            silentChunks += 1
        }

        recent.append((decibels, seconds))
        var covered = recent.reduce(0) { $0 + $1.seconds }
        while recent.count > 1, covered - recent[0].seconds >= Self.floorWindow {
            covered -= recent.removeFirst().seconds
        }
        let floor = currentFloor
        let gate = floor + Self.gate

        if decibels > ceiling {
            ceiling += min((decibels - ceiling) * Self.ceilingAttack, Self.largestCeilingRise)
        } else {
            ceiling -= Self.ceilingRelease * seconds
        }
        ceiling = min(max(ceiling, Self.lowestCeiling, gate + Self.narrowestSpan), Self.highestCeiling)

        let bottom = max(gate, ceiling - Self.widestSpan)
        let level = Float(min(max((decibels - bottom) / (ceiling - bottom), 0), 1))

        inputs.append(decibels)
        shown.append(level)
        return level
    }

    private var currentFloor: Double {
        let quietest = recent.map(\.decibels).min() ?? Self.lowestFloor
        return min(max(quietest, Self.lowestFloor), Self.highestFloor)
    }

    public var statistics: Statistics {
        guard !inputs.isEmpty else { return Statistics() }
        let sortedInputs = inputs.sorted()
        let audible = shown.filter { $0 > 0 }.sorted()
        var statistics = Statistics()
        statistics.chunks = inputs.count
        statistics.audibleChunks = audible.count
        statistics.silentChunks = silentChunks
        statistics.leadingSilentChunks = leadingSilentChunks
        statistics.leadingSilentSeconds = leadingSilentSeconds
        statistics.quietestInput = sortedInputs[0]
        statistics.medianInput = sortedInputs[sortedInputs.count / 2]
        statistics.ninetiethPercentileInput = sortedInputs[min(sortedInputs.count - 1, sortedInputs.count * 9 / 10)]
        statistics.loudestInput = sortedInputs[sortedInputs.count - 1]
        statistics.floor = currentFloor
        statistics.ceiling = ceiling
        if !audible.isEmpty {
            statistics.medianShown = audible[audible.count / 2]
            statistics.ninetiethPercentileShown = audible[min(audible.count - 1, audible.count * 9 / 10)]
            statistics.highestShown = audible[audible.count - 1]
        }
        return statistics
    }
}
