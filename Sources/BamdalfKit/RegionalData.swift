/// Completed query coverage and its complete, unsampled records for one BAM.
/// Geometry extending beyond this coverage never establishes readiness.
struct RegionalData {
    private struct Entry {
        let interval: GenomicInterval
        let records: [Alignment]
        var storageBytes: Int {
            256 + 2 * interval.reference.utf8.count + records.reduce(0) { $0 + $1.estimatedStorageBytes }
        }
    }
    private var entries: [Entry] = []
    private let historicalLimit: Int?

    init(historicalLimit: Int? = 8) { self.historicalLimit = historicalLimit }

    mutating func insert(_ records: [Alignment], for interval: GenomicInterval, keeping activeTarget: GenomicInterval) {
        if historicalLimit == nil {
            // Maintain disjoint completed coverage. Overlapping historical
            // snapshots must not all become protected just because each touches R.
            entries = entries.flatMap { entry -> [Entry] in
                entry.interval.subtracting(interval).map {
                    Self.fragment(entry, start: $0.start, end: $0.end)
                }
            }
            entries.append(Entry(interval: interval, records: records))
            return
        }
        entries.removeAll {
            $0.interval.reference == interval.reference && $0.interval.start >= interval.start && $0.interval.end <= interval.end
        }
        entries.append(Entry(interval: interval, records: records))
        guard let historicalLimit else { return }
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
            guard historicalCount > historicalLimit, !isActive(entry) else { return false }
            historicalCount -= 1
            return true
        }
    }

    func available(for target: GenomicInterval) -> (records: [Alignment], missing: [GenomicInterval]) {
        let applicable = entries.filter { $0.interval.reference == target.reference }
        let records = Self.eligible(applicable.flatMap(\.records), for: target)
        return (records, missingCoverage(for: target))
    }

    func missingCoverage(for target: GenomicInterval) -> [GenomicInterval] {
        let applicable = entries.filter { $0.interval.reference == target.reference }
        var missing: [GenomicInterval] = []
        var next = target.start
        for entry in applicable.sorted(by: { $0.interval.start < $1.interval.start }) {
            let covered = entry.interval
            guard covered.end >= next, covered.start <= target.end else { continue }
            if covered.start > next {
                missing.append(GenomicInterval(reference: target.reference, start: next, end: covered.start - 1))
            }
            if covered.end >= target.end { return missing }
            next = covered.end + 1
        }
        if next <= target.end { missing.append(GenomicInterval(reference: target.reference, start: next, end: target.end)) }
        return missing
    }

    /// Current required coverage and committed recovery data are never charged
    /// to (or discarded for) the optional budget. All other retained queries are.
    mutating func trimOptional(keeping required: GenomicInterval?, recovery: GenomicInterval?, maximumBytes: Int) {
        // Split at protection boundaries so optional tails of a once-required
        // query also consume the optional budget. Full records remain attached
        // to every fragment whose aligned coverage they intersect.
        for target in [required, recovery].compactMap({ $0 }) {
            entries = entries.flatMap { entry -> [Entry] in
                guard entry.interval.reference == target.reference else { return [entry] }
                var fragments: [Entry] = []
                var start = entry.interval.start
                let boundaries = target.end == .max ? [target.start] : [target.start, target.end + 1]
                for boundary in boundaries where boundary > start && boundary <= entry.interval.end {
                    fragments.append(Self.fragment(entry, start: start, end: boundary - 1))
                    start = boundary
                }
                fragments.append(Self.fragment(entry, start: start, end: entry.interval.end))
                return fragments
            }
        }
        func protected(_ entry: Entry) -> Bool {
            [required, recovery].compactMap { $0 }.contains { target in
                entry.interval.reference == target.reference
                    && entry.interval.start <= target.end && entry.interval.end >= target.start
            }
        }
        func distance(_ entry: Entry) -> Int64 {
            guard let required else { return .max }
            return entry.interval.distance(to: required)
        }
        var optionalBytes = entries.filter { !protected($0) }.reduce(0) { $0 + $1.storageBytes }
        let evictionOrder = entries.indices.filter { !protected(entries[$0]) }.sorted {
            let left = distance(entries[$0]), right = distance(entries[$1])
            return left == right ? $0 < $1 : left > right
        }
        var evicted = Set<Int>()
        for index in evictionOrder where optionalBytes > maximumBytes {
            optionalBytes -= entries[index].storageBytes
            evicted.insert(index)
        }
        entries = entries.enumerated().filter { !evicted.contains($0.offset) }.map(\.element)
    }

    private static func fragment(_ entry: Entry, start: Int64, end: Int64) -> Entry {
        guard start != entry.interval.start || end != entry.interval.end else { return entry }
        let interval = GenomicInterval(reference: entry.interval.reference, start: start, end: end)
        return Entry(interval: interval, records: eligible(entry.records, for: interval))
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
