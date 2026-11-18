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
    public var drawnStart: Int64 { segments.lazy.map(\.start).min() ?? referenceStart }
    public var drawnEnd: Int64 { (segments.lazy.map(\.end).max() ?? (referenceEnd + 1)) - 1 }

    func overlapsViewport(_ target: GenomicInterval) -> Bool {
        drawnStart <= target.end && drawnEnd >= target.start
    }

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

/// The stored letter is retained even when an ambiguous reference determines its color.
struct BaseDifference {
    let position: Int64
    let base: UInt8
    let isIndeterminate: Bool

    init?(position: Int64, stored: UInt8, reference: UInt8) {
        let referenceBase = CanonicalBase(reference)
        let alignedBase = CanonicalBase(stored)
        // A stored '=' declares agreement only against an unambiguous reference.
        if let referenceBase, stored == 61 || alignedBase == referenceBase { return nil }
        self.position = position
        self.base = stored
        self.isIndeterminate = referenceBase == nil || alignedBase == nil
    }
}

enum CanonicalBase: UInt8 {
    case a = 65, c = 67, g = 71, t = 84

    init?(_ ascii: UInt8) {
        self.init(rawValue: ascii & 0xDF) // Fold ASCII letter case.
    }
}

extension Alignment {
    /// Group the colored cells by aligned segment so the renderer can clip them to its strand geometry.
    func differences(in region: ReferenceRegion) -> [Int64: [BaseDifference]] {
        var result: [Int64: [BaseDifference]] = [:]
        region.bases.withUnsafeBytes { (reference: UnsafeRawBufferPointer) in
            for segment in segments where segment.kind == .aligned {
                guard var sequence = segment.sequence else { continue }
                let start = max(segment.start, region.interval.start)
                let last = min(segment.end - 1, region.interval.end)
                guard start <= last else { continue }
                let referenceOffset = Int(start - region.interval.start)
                let count = min(Int(last - start + 1), reference.count - referenceOffset)
                guard count > 0 else { continue }
                let queryOffset = Int(start - segment.start)
                let cells = sequence.withUTF8 { query in
                    (0..<count).compactMap { offset in
                        BaseDifference(position: start + Int64(offset), stored: query[queryOffset + offset],
                                       reference: reference[referenceOffset + offset])
                    }
                }
                if !cells.isEmpty { result[segment.start] = cells }
            }
        }
        return result
    }
}
