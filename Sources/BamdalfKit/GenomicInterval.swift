import Foundation

/// A genomic target with 1-based inclusive endpoints, matching input and display.
public struct GenomicInterval: Equatable, Sendable {
    public let reference: String
    public let start: Int64
    public let end: Int64

    public init(reference: String, start: Int64, end: Int64) {
        self.reference = reference
        self.start = start
        self.end = end
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end && lhs.hasSameReference(as: rhs)
    }

    func hasSameReference(as other: Self) -> Bool {
        reference.utf8.elementsEqual(other.reference.utf8)
    }

    /// Screen points per base when the viewport can show individual reference cells.
    func referenceScale(in width: Double) -> Double? {
        let scale = width / Double(end - start + 1)
        return scale >= 1 ? scale : nil
    }

    public var formatted: String {
        "\(reference):\(formatCoordinate(start))-\(formatCoordinate(end))"
    }

    func subtracting(_ excluded: GenomicInterval) -> [GenomicInterval] {
        guard hasSameReference(as: excluded), excluded.end >= start, excluded.start <= end else { return [self] }
        var remaining: [GenomicInterval] = []
        if excluded.start > start {
            remaining.append(GenomicInterval(reference: reference, start: start, end: excluded.start - 1))
        }
        if excluded.end < end {
            remaining.append(GenomicInterval(reference: reference, start: excluded.end + 1, end: end))
        }
        return remaining
    }

    func distance(to other: GenomicInterval) -> Int64 {
        guard hasSameReference(as: other) else { return .max }
        return max(0, max(start - other.end, other.start - end))
    }

    static func parse(_ input: String, references: [ReferenceSequence]) throws -> GenomicInterval {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: \.isWhitespace), let separator = text.lastIndex(of: ":") else {
            throw IntervalValidationError("Use reference:start-end with no internal spaces.")
        }
        let reference = String(text[..<separator])
        let range = text[text.index(after: separator)...].split(separator: "-", omittingEmptySubsequences: false)
        guard range.count == 2, let start = parseCoordinate(range[0]), let end = parseCoordinate(range[1]) else {
            throw IntervalValidationError("Use whole base coordinates, optional thousands commas, and a regular hyphen.")
        }
        guard let sequence = references.contig(named: reference) else {
            throw IntervalValidationError("Reference name must exactly match a contig in the selected file.")
        }
        guard start >= 1 else { throw IntervalValidationError("Start must be at least 1.") }
        guard start <= end else { throw IntervalValidationError("Start must be at or before end.") }
        guard end <= sequence.length else {
            throw IntervalValidationError("End must not exceed \(formatCoordinate(sequence.length)) for \(reference).")
        }
        return GenomicInterval(reference: reference, start: start, end: end)
    }
}

struct IntervalValidationError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private func parseCoordinate(_ text: Substring) -> Int64? {
    let groups = text.split(separator: ",", omittingEmptySubsequences: false)
    guard groups.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
    if groups.count > 1 {
        guard groups[0].count <= 3, groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
    }
    return Int64(groups.joined())
}

func formatCoordinate(_ coordinate: Int64) -> String {
    coordinate.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
}

extension Array where Element == ReferenceSequence {
    func contig(named name: String) -> ReferenceSequence? {
        first { $0.name.utf8.elementsEqual(name.utf8) }
    }
}
