/// Completed query coverage and its complete, unsampled records for one BAM.
/// Geometry extending beyond this coverage never establishes readiness.
struct RegionalData {
    private struct Entry {
        let interval: GenomicInterval
        let records: [Alignment]
    }
    private var entries: [Entry] = []

    mutating func insert(_ records: [Alignment], for interval: GenomicInterval) {
        entries.removeAll {
            $0.interval.reference == interval.reference && $0.interval.start >= interval.start && $0.interval.end <= interval.end
        }
        entries.append(Entry(interval: interval, records: records))
        // Bound historical query snapshots, not the number of eligible records.
        if entries.count > 8 { entries.removeFirst(entries.count - 8) }
    }

    func available(for target: GenomicInterval) -> (records: [Alignment], missing: [GenomicInterval]) {
        let applicable = entries.filter { $0.interval.reference == target.reference }
        let records = Self.eligible(applicable.flatMap(\.records), for: target)
        var missing: [GenomicInterval] = []
        var next = target.start
        for entry in applicable.sorted(by: { $0.interval.start < $1.interval.start }) {
            let covered = entry.interval
            guard covered.end >= next, covered.start <= target.end else { continue }
            if covered.start > next {
                missing.append(GenomicInterval(reference: target.reference, start: next, end: covered.start - 1))
            }
            if covered.end >= target.end { return (records, missing) }
            next = covered.end + 1
        }
        if next <= target.end { missing.append(GenomicInterval(reference: target.reference, start: next, end: target.end)) }
        return (records, missing)
    }

    static func eligible(_ records: [Alignment], for target: GenomicInterval) -> [Alignment] {
        var unique: [UInt64: Alignment] = [:]
        for record in records where record.referenceStart <= target.end && record.referenceEnd >= target.start {
            unique[record.id] = record
        }
        return Array(unique.values)
    }
}
