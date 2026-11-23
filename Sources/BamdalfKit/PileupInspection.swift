import Foundation

struct BaseCounts {
    private var canonical: [CanonicalBase: Int] = [:]
    private var ambiguous = 0
    private var unresolved = 0

    private var deletions = 0
    private var skips = 0
    private var unavailable = 0
    private var insertions = 0

    init(records: [Alignment], position: Int64, reference: UInt8?) {
        for record in records {
            // Padded CIGARs can contain multiple insertion operations at the same boundary.
            if record.segments.contains(where: { $0.kind == .insertion && $0.start - 1 == position }) {
                insertions += 1
            }
            for segment in record.segments where segment.start <= position && position < segment.end {
                switch segment.kind {
                case .aligned:
                    guard var sequence = segment.sequence else {
                        unavailable += 1
                        continue
                    }
                    let symbol = sequence.withUTF8 { $0[Int(position - segment.start)] }
                    countBase(symbol, reference: reference)
                case .deletion: deletions += 1
                case .skip: skips += 1
                case .softClip, .insertion: break
                }
            }
        }
    }

    private mutating func countBase(_ symbol: UInt8, reference: UInt8?) {
        let base = (symbol == 61 ? reference : symbol).flatMap { CanonicalBase($0) }
        if let base {
            canonical[base, default: 0] += 1
        } else if symbol == 61 {
            unresolved += 1
        } else {
            ambiguous += 1
        }
    }

    var summary: String {
        let depth = canonical.values.reduce(ambiguous + unresolved, +)
        func category(_ name: String, _ count: Int) -> String {
            guard depth > 0 else { return "\(name) \(count)" }
            let percent = (Double(count) / Double(depth)).formatted(.percent.locale(Locale(identifier: "en_US")).precision(.fractionLength(0...2)))
            return "\(name) \(count) (\(percent))"
        }
        var fields = ["Base depth \(depth)"]
        for base in [CanonicalBase.a, .c, .g, .t] {
            fields.append(category(String(UnicodeScalar(base.rawValue)), canonical[base, default: 0]))
        }
        if ambiguous > 0 { fields.append(category("Ambiguous", ambiguous)) }
        if unresolved > 0 { fields.append(category("Unresolved =", unresolved)) }
        if deletions > 0 { fields.append("Deletions \(deletions)") }
        if skips > 0 { fields.append("Reference skips \(skips)") }
        if unavailable > 0 { fields.append("Sequence unavailable \(unavailable)") }
        if insertions > 0 { fields.append("Insertion after this base \(insertions)") }
        return fields.joined(separator: "   ")
    }
}

struct PileupInspection {
    let position: GenomicInterval
    var reference: UInt8?
    enum Status { case loading, ready(BaseCounts), unavailable }
    var status: Status = .loading

    var heading: String {
        let coordinate = "\(position.reference):\(formatCoordinate(position.start))"
        return reference.map { "\(coordinate) · Reference \(UnicodeScalar($0))" } ?? coordinate
    }

    var detail: String {
        switch status {
        case .loading: "Loading…"
        case .unavailable: "Counts unavailable"
        case .ready(let counts): counts.summary
        }
    }
}
