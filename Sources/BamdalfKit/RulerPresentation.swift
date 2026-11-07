import Foundation

public struct RulerTick: Equatable, Sendable {
    public let coordinate: Int64
    public let fraction: Double
    public var label: String { formatCoordinate(coordinate) }
}

extension ViewerPresentation {
    /// Full-coordinate labels at 1/2/5 steps, positioned at base centers.
    public func rulerTicks(availableWidth: Double) -> [RulerTick] {
        guard let target, availableWidth.isFinite, availableWidth > 0 else { return [] }
        let span = target.end - target.start + 1
        if span == 1 { return [RulerTick(coordinate: target.start, fraction: 0.5)] }
        let labelSpacing = Double(max(80, formatCoordinate(target.end).count * 8 + 24))
        let labelCount = max(1, floor(availableWidth / labelSpacing))
        let step = rulerStep(atLeast: Double(span) / labelCount)
        let remainder = target.start % step
        let offset = remainder == 0 ? 0 : step - remainder
        guard offset <= target.end - target.start else {
            let center = target.start + (span - 1) / 2
            return [RulerTick(coordinate: center, fraction: (Double(center - target.start) + 0.5) / Double(span))]
        }
        var coordinate = target.start + offset
        var ticks: [RulerTick] = []
        while coordinate <= target.end {
            ticks.append(RulerTick(coordinate: coordinate, fraction: (Double(coordinate - target.start) + 0.5) / Double(span)))
            guard step <= target.end - coordinate else { break }
            coordinate += step
        }
        return ticks
    }
}

private func rulerStep(atLeast minimum: Double) -> Int64 {
    var magnitude: Int64 = 1
    while true {
        for multiplier: Int64 in [1, 2, 5] {
            let (step, overflow) = magnitude.multipliedReportingOverflow(by: multiplier)
            if overflow { return Int64.max }
            if Double(step) >= minimum { return step }
        }
        let (next, overflow) = magnitude.multipliedReportingOverflow(by: 10)
        if overflow { return Int64.max }
        magnitude = next
    }
}
