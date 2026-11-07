import Foundation

/// A genomic target with 1-based inclusive endpoints, matching input and display.
public struct GenomicInterval: Equatable, Sendable {
    public let reference: String
    public let start: Int64
    public let end: Int64

    public var formatted: String {
        "\(reference):\(formatCoordinate(start))-\(formatCoordinate(end))"
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
        guard let sequence = references.first(where: { $0.name == reference }) else {
            throw IntervalValidationError("Reference name must exactly match a reference in this BAM.")
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
