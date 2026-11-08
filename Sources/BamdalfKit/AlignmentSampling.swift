import CryptoKit
import Foundation

/// Whole-target selection. Complete candidates remain owned by RegionalData.
struct AlignmentSampling {
    private struct Identity: Hashable {
        let bytes: [UInt8]

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }

        func hash(into hasher: inout Hasher) {
            bytes.withUnsafeBytes { hasher.combine(bytes: $0) }
        }
    }

    let budget: Int
    var seed: UInt64 = 0 {
        didSet { groupPriorities.removeAll() }
    }
    let priority: @Sendable (UInt64, [UInt8]) -> UInt64
    // Only the immediately preceding candidate groups are retained. Replacing
    // this map on every selection avoids an inventory of past navigations.
    private var groupPriorities: [Identity: UInt64] = [:]

    init(budget: Int, priority: (@Sendable (UInt64, [UInt8]) -> UInt64)?) {
        precondition(budget > 0)
        self.budget = budget
        self.priority = priority ?? Self.hashPriority
    }

    mutating func select(_ records: [Alignment]) -> (records: [Alignment], isDownsampled: Bool) {
        let identities = records.map { Identity(bytes: Self.identity($0)) }
        let groups = Set(identities)
        guard groups.count > budget else {
            groupPriorities.removeAll()
            return (records, false)
        }
        var nextPriorities: [Identity: UInt64] = [:]
        nextPriorities.reserveCapacity(groups.count)
        let ranked = groups.map { identity in
            let value = groupPriorities[identity] ?? priority(seed, identity.bytes)
            nextPriorities[identity] = value
            return (identity: identity, priority: value)
        }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.identity.bytes.lexicographicallyPrecedes($1.identity.bytes)
        }
        groupPriorities = nextPriorities
        let retained = Set(ranked.prefix(budget).map(\.identity))
        return (zip(records, identities).compactMap { retained.contains($1) ? $0 : nil }, true)
    }

    // Tags distinguish unnamed records, absent RG, and present RG (including empty).
    // Length-prefixed UTF-8 strings and big-endian UInt64 integers are unambiguous.
    private static func identity(_ record: Alignment) -> [UInt8] {
        var result: [UInt8] = []
        if record.name == "*" {
            result.reserveCapacity(9)
            result.append(0)
            appendBigEndian(record.id, to: &result)
            return result
        }
        let name = record.name.utf8
        if let group = record.readGroup?.utf8 {
            result.reserveCapacity(17 + group.count + name.count)
            result.append(2)
            appendBigEndian(UInt64(group.count), to: &result)
            result.append(contentsOf: group)
        } else {
            result.reserveCapacity(9 + name.count)
            result.append(1)
        }
        appendBigEndian(UInt64(name.count), to: &result)
        result.append(contentsOf: name)
        return result
    }

    private static func appendBigEndian(_ value: UInt64, to bytes: inout [UInt8]) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
    }

    private static func hashPriority(seed: UInt64, identity: [UInt8]) -> UInt64 {
        var hash = SHA256()
        var seed = seed.bigEndian
        withUnsafeBytes(of: &seed) { hash.update(bufferPointer: $0) }
        identity.withUnsafeBytes { hash.update(bufferPointer: $0) }
        return hash.finalize().prefix(8).reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
