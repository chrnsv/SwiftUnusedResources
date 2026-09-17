import Foundation

/// Timing summary in seconds.
package struct Summary: Codable, Equatable, Sendable {
    package var min: Double
    package var median: Double
    package var p90: Double
    package var max: Double

    package init(min: Double, median: Double, p90: Double, max: Double) {
        self.min = min
        self.median = median
        self.p90 = p90
        self.max = max
    }
}

package func summarize(_ samples: [Double]) -> Summary? {
    guard let min = samples.min(), let max = samples.max() else {
        return nil
    }

    let sorted = samples.sorted()
    let middle = sorted.count / 2
    let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]

    // Nearest-rank percentile
    let rank = Int((0.9 * Double(sorted.count)).rounded(.up))
    let p90 = sorted[Swift.max(rank, 1) - 1]

    return Summary(min: min, median: median, p90: p90, max: max)
}

package func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
