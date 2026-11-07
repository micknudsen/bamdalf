import Foundation
import CBAM

public struct ReferenceSequence: Equatable, Sendable {
    public let name: String
    public let length: Int64
}

/// Owns one opened BAM/header/index. Native access stays inside this actor.
public actor BAMFile {
    public nonisolated let url: URL
    public nonisolated let indexURL: URL
    public nonisolated let references: [ReferenceSequence]
    private let handle: BAMHandle

    public static func open(_ url: URL, indexURL: URL) async throws -> BAMFile {
        try await Task.detached { try BAMFile(url, indexURL: indexURL) }.value
    }

    public func alignments(in interval: GenomicInterval) throws -> [Alignment] {
        guard let query = bamdalf_query_open(handle.pointer, interval.reference, interval.start - 1, interval.end) else {
            throw RegionalLoadError(interval: interval, message: "Could not query the selected BAM index.")
        }
        defer { bamdalf_query_close(query) }
        var result: [Alignment] = []
        while true {
            let status = bamdalf_query_next(query)
            if status == -1 { return result }
            guard status >= 0 else {
                throw RegionalLoadError(interval: interval, message: "Could not decode alignment data from the selected BAM/index.")
            }
            let flags = bamdalf_record_flags(query)
            if flags & 0x704 != 0 { continue }
            let name = String(cString: bamdalf_record_name(query))
            guard bamdalf_record_cigar_count(query) > 0 else {
                throw RegionalLoadError(interval: interval, message: "Mapped alignment \(name) has no CIGAR.")
            }
            let start = bamdalf_record_start(query) + 1
            var reference = start
            var queryOffset = 0
            let sequenceLength = Int(bamdalf_record_sequence_length(query))
            let sequence = (0..<sequenceLength).map { UInt8(bitPattern: bamdalf_record_base(query, Int32($0))) }
            var segments: [AlignmentSegment] = []
            var cigar = ""
            for index in 0..<bamdalf_record_cigar_count(query) {
                let operation = bamdalf_record_cigar(query, index)
                let length = Int(operation >> 4)
                guard length > 0 else {
                    throw RegionalLoadError(interval: interval, message: "Invalid zero-length CIGAR operation for \(name).")
                }
                let code = operation & 15
                let symbols = Array("MIDNSHP=X")
                guard code < symbols.count else {
                    throw RegionalLoadError(interval: interval, message: "Invalid CIGAR operation for \(name).")
                }
                cigar += "\(length)\(symbols[Int(code)])"
                switch code {
                case 0, 7, 8:
                    segments.append(AlignmentSegment(kind: .aligned, start: reference, end: reference + Int64(length), sequence: nil))
                    reference += Int64(length)
                    queryOffset += length
                case 1:
                    segments.append(AlignmentSegment(kind: .insertion, start: reference, end: reference, sequence: nil))
                    queryOffset += length
                case 2, 3:
                    segments.append(AlignmentSegment(kind: code == 2 ? .deletion : .skip,
                                                     start: reference, end: reference + Int64(length), sequence: nil))
                    reference += Int64(length)
                case 5, 6:
                    break
                case 4:
                    guard sequenceLength == 0 || queryOffset + length <= sequenceLength else {
                        throw RegionalLoadError(interval: interval, message: "CIGAR and sequence lengths differ for \(name).")
                    }
                    let bases = sequenceLength == 0 ? nil : String(decoding: sequence[queryOffset..<(queryOffset + length)], as: UTF8.self)
                    let tailStart = reference == start ? start - Int64(length) : reference
                    segments.append(AlignmentSegment(kind: .softClip, start: tailStart, end: tailStart + Int64(length), sequence: bases))
                    queryOffset += length
                default:
                    throw RegionalLoadError(interval: interval, message: "Cannot interpret CIGAR for \(name).")
                }
            }
            guard sequenceLength == 0 || queryOffset == sequenceLength else {
                throw RegionalLoadError(interval: interval, message: "CIGAR and sequence lengths differ for \(name).")
            }
            guard start >= 1, let referenceLength = references.first(where: { $0.name == interval.reference })?.length,
                  reference - 1 <= referenceLength else {
                throw RegionalLoadError(interval: interval, message: "Alignment \(name) exceeds the reference bounds.")
            }
            if reference > start && start <= interval.end && reference > interval.start {
                result.append(Alignment(id: bamdalf_record_id(query), name: name, cigar: cigar, isReverse: flags & 16 != 0,
                                        referenceStart: start, referenceEnd: reference - 1, segments: segments))
            }
        }
    }

    private init(_ url: URL, indexURL: URL) throws {
        var message = [CChar](repeating: 0, count: 1024)
        var indexFailed: Int32 = 0
        guard let pointer = bamdalf_bam_open(url.path, indexURL.path, &message, message.count, &indexFailed) else {
            throw FileOpenError(fileURL: indexFailed == 0 ? url : indexURL,
                                message: String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        handle = BAMHandle(pointer)
        self.url = url
        self.indexURL = indexURL
        references = (0..<bamdalf_reference_count(pointer)).map { reference in
            ReferenceSequence(name: String(cString: bamdalf_reference_name(pointer, reference)),
                              length: bamdalf_reference_length(pointer, reference))
        }
    }
}

// Only BAMFile owns/uses this handle. The wrapper permits safe destruction when
// the actor's last reference is released on a different executor.
private final class BAMHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { bamdalf_bam_close(pointer) }
}
