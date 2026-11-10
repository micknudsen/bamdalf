/// Completed query coverage and its complete, unsampled records for one BAM.
/// Geometry extending beyond this coverage never establishes readiness.
struct RegionalData {
    private struct Entry {
        let interval: GenomicInterval
        let records: [Alignment]
    }
    private var entries: [Entry] = []

    mutating func insert(_ records: [Alignment], for interval: GenomicInterval, keeping activeTarget: GenomicInterval) {
        entries.removeAll {
            $0.interval.reference == interval.reference && $0.interval.start >= interval.start && $0.interval.end <= interval.end
        }
        entries.append(Entry(interval: interval, records: records))
        // Active coverage/candidates remain available independently of the
        // bounded historical snapshots. Even a disjoint query may hold a long
        // alignment eligible for the active target.
        func isActive(_ entry: Entry) -> Bool {
            guard entry.interval.reference == activeTarget.reference else { return false }
            return (entry.interval.start <= activeTarget.end && entry.interval.end >= activeTarget.start)
                || entry.records.contains { $0.referenceStart <= activeTarget.end && $0.referenceEnd >= activeTarget.start }
        }
        var historicalCount = entries.filter { !isActive($0) }.count
        entries.removeAll { entry in
            guard historicalCount > 8, !isActive(entry) else { return false }
            historicalCount -= 1
            return true
        }
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
        var seen: Set<UInt64> = []
        var result: [Alignment] = []
        for record in records where record.referenceStart <= target.end && record.referenceEnd >= target.start {
            if seen.insert(record.id).inserted { result.append(record) }
        }
        return result
    }

    /// Apply drawn overlap only after selecting aligned spans within required
    /// search coverage. These display candidates never back a coverage claim.
    static func visible(_ records: [Alignment], in target: GenomicInterval) -> [Alignment] {
        records.filter { $0.drawnStart <= target.end && $0.drawnEnd >= target.start }
    }
}
