import Foundation

public struct AlignmentSegment: Equatable, Sendable {
    public enum Kind: Sendable { case aligned, softClip, insertion, deletion, skip }
    public let kind: Kind
    /// One-based start and exclusive end, including unaligned drawn tails.
    public let start: Int64
    public let end: Int64
    public let sequence: String?
}

public struct Alignment: Equatable, Sendable, Identifiable {
    /// BAM virtual offset after the record, stable across indexed queries.
    public let id: UInt64
    public internal(set) var row = 0
    public let name: String
    public let readGroup: String?
    public let cigar: String
    public let isReverse: Bool
    public let referenceStart: Int64
    public let referenceEnd: Int64
    public let segments: [AlignmentSegment]
    public var drawnStart: Int64 { segments.map(\.start).min() ?? referenceStart }
    public var drawnEnd: Int64 { (segments.map(\.end).max() ?? (referenceEnd + 1)) - 1 }

    /// Conservative app-owned storage accounting, not process RSS. Twice the
    /// inline/array/string payload allows spare capacity, plus allocation
    /// overhead (256 bytes per record and 32 per segment). Shared copy-on-write
    /// payloads are deliberately counted again by each cache entry retaining them.
    var estimatedStorageBytes: Int {
        2 * MemoryLayout<Self>.stride + 256
            + 2 * (name.utf8.count + (readGroup?.utf8.count ?? 0) + cigar.utf8.count)
            + 2 * segments.count * MemoryLayout<AlignmentSegment>.stride
            + segments.reduce(0) { $0 + 32 + 2 * ($1.sequence?.utf8.count ?? 0) }
    }
}

public struct RegionalLoadError: Error, Equatable, Sendable {
    public let id: UUID
    public let interval: GenomicInterval
    public let message: String

    public init(interval: GenomicInterval, message: String) {
        self.init(id: UUID(), interval: interval, message: message)
    }

    init(id: UUID, interval: GenomicInterval, message: String) {
        self.id = id
        self.interval = interval
        self.message = message
    }
}
