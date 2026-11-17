import Foundation

/// Regroups PCM bytes of arbitrary sizes into fixed-size chunks for streaming.
public struct AudioChunker: Sendable {
    public let chunkByteCount: Int
    private var buffer = Data()

    public init(chunkByteCount: Int) {
        precondition(chunkByteCount > 0)
        self.chunkByteCount = chunkByteCount
    }

    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var chunks: [Data] = []
        while buffer.count >= chunkByteCount {
            chunks.append(Data(buffer.prefix(chunkByteCount)))
            buffer.removeFirst(chunkByteCount)
        }
        return chunks
    }

    /// Returns whatever is left over, shorter than a full chunk.
    public mutating func flush() -> Data? {
        guard !buffer.isEmpty else { return nil }
        defer { buffer = Data() }
        return buffer
    }
}
