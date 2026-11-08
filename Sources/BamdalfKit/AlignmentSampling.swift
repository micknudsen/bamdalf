import CryptoKit
import Foundation

/// Whole-target selection. Complete candidates remain owned by RegionalData.
struct AlignmentSampling {
    let budget: Int
    var seed: UInt64 = 0
    let priority: @Sendable (UInt64, [UInt8]) -> UInt64

    init(budget: Int, priority: (@Sendable (UInt64, [UInt8]) -> UInt64)?) {
        precondition(budget > 0)
        self.budget = budget
        self.priority = priority ?? Self.hashPriority
    }

    func select(_ records: [Alignment]) -> (records: [Alignment], isDownsampled: Bool) {
        let identities = records.map(Self.identity)
        let groups = Set(identities)
        guard groups.count > budget else { return (records, false) }
        let ranked = groups.map { (identity: $0, priority: priority(seed, $0)) }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.identity.lexicographicallyPrecedes($1.identity)
        }
        let retained = Set(ranked.prefix(budget).map(\.identity))
        return (zip(records, identities).compactMap { retained.contains($1) ? $0 : nil }, true)
    }

    // Tags distinguish unnamed records, absent RG, and present RG (including empty).
    // Length-prefixed UTF-8 strings and big-endian UInt64 integers are unambiguous.
    private static func identity(_ record: Alignment) -> [UInt8] {
        if record.name == "*" { return [0] + bytes(record.id) }
        let name = Array(record.name.utf8)
        guard let readGroup = record.readGroup else { return [1] + bytes(UInt64(name.count)) + name }
        let group = Array(readGroup.utf8)
        return [2] + bytes(UInt64(group.count)) + group + bytes(UInt64(name.count)) + name
    }

    private static func bytes(_ value: UInt64) -> [UInt8] {
        (0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    private static func hashPriority(seed: UInt64, identity: [UInt8]) -> UInt64 {
        SHA256.hash(data: Data(bytes(seed) + identity)).prefix(8).reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
