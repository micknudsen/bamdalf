/// Engineering limits for optional adjacent loading, independent of display sampling.
public struct PrefetchConfiguration: Sendable {
    public static let disabled = PrefetchConfiguration(maximumBytes: 0)

    let maximumBytes: Int
    let maximumQueryBytes: Int
    let maximumQueryRecords: Int
    let chunkBases: Int64

    public init(maximumBytes: Int = 32 * 1_024 * 1_024,
                maximumQueryBytes: Int = 8 * 1_024 * 1_024,
                maximumQueryRecords: Int = 20_000, chunkBases: Int64 = 1_000) {
        precondition(maximumBytes >= 0 && maximumQueryBytes > 0 && maximumQueryRecords > 0 && chunkBases > 0)
        self.maximumBytes = maximumBytes
        self.maximumQueryBytes = maximumQueryBytes
        self.maximumQueryRecords = maximumQueryRecords
        self.chunkBases = chunkBases
    }
}
