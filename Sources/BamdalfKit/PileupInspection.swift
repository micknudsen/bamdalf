import Foundation

struct BaseCounts {
    private var canonical: [CanonicalBase: Int] = [:]
    private var ambiguous = 0
    private var unresolved = 0

    init(records: [Alignment], position: Int64, reference: UInt8?) {
        for record in records {
            guard let segment = record.segments.first(where: {
                $0.kind == .aligned && $0.start <= position && position < $0.end
            }), var sequence = segment.sequence else { continue }
            let symbol = sequence.withUTF8 { $0[Int(position - segment.start)] }
            let base = (symbol == 61 ? reference : symbol).flatMap { CanonicalBase($0) }
            if let base {
                canonical[base, default: 0] += 1
            } else if symbol == 61 {
                unresolved += 1
            } else {
                ambiguous += 1
            }
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
