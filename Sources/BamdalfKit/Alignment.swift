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
    public let cigar: String
    public let isReverse: Bool
    public let referenceStart: Int64
    public let referenceEnd: Int64
    public let segments: [AlignmentSegment]
    public var drawnStart: Int64 { segments.map(\.start).min() ?? referenceStart }
    public var drawnEnd: Int64 { (segments.map(\.end).max() ?? (referenceEnd + 1)) - 1 }
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
