import Foundation

/// Builds one transcript from the finalized results of a streaming session.
///
/// The server finalizes speech in chunks and may later send a longer result that restates earlier
/// chunks (an utterance-final result, or the closing `transcript.done`). Results are therefore
/// keyed by the stretch of audio they cover: a new result replaces the earlier ones inside it, and
/// a result that falls inside one already held is a repeat and is dropped.
public struct TranscriptAssembler: Sendable {
    private struct Segment: Sendable {
        var range: ClosedRange<Double>
        var text: String

        var midpoint: Double { (range.lowerBound + range.upperBound) / 2 }
        var length: Double { range.upperBound - range.lowerBound }

        func covers(_ other: Segment) -> Bool {
            let tolerance = 0.05
            return other.midpoint >= range.lowerBound - tolerance
                && other.midpoint <= range.upperBound + tolerance
                && length >= other.length - tolerance
        }
    }

    private var segments: [Segment] = []

    public init() {}

    public var text: String {
        segments.map(\.text).joined(separator: " ")
    }

    public mutating func apply(_ partial: STTServerEvent.Partial) {
        guard partial.isFinal else { return }
        insert(text: partial.text, range: partial.range)
    }

    /// Folds in the closing `transcript.done` and returns the complete transcript.
    public mutating func finish(with done: STTServerEvent.Done) -> String {
        let doneText = done.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !doneText.isEmpty else { return text }
        guard let range = done.range else {
            // Without word timings there is nothing to align on; the docs describe this text as the full transcript.
            return doneText
        }
        insert(text: doneText, range: range)
        return text
    }

    private mutating func insert(text: String, range: ClosedRange<Double>) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let new = Segment(range: range, text: trimmed)
        let replaced = segments.filter { new.covers($0) }
        if replaced.isEmpty, segments.contains(where: { $0.covers(new) }) {
            return
        }
        segments.removeAll { new.covers($0) }
        segments.append(new)
        segments.sort { $0.range.lowerBound < $1.range.lowerBound }
    }
}
