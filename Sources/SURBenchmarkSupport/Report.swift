import Foundation

package struct Report: Codable, Equatable {
    package var revision: String
    package var workload: String
    package var date: Date
    package var entries: [Entry]

    package init(revision: String, workload: String, date: Date, entries: [Entry]) {
        self.revision = revision
        self.workload = workload
        self.date = date
        self.entries = entries
    }

    package struct Entry: Codable, Equatable {
        package var name: String
        package var iterations: Int
        package var summary: Summary

        package init(name: String, iterations: Int, summary: Summary) {
            self.name = name
            self.iterations = iterations
            self.summary = summary
        }
    }
}

package struct Delta: Equatable {
    package var name: String
    package var baselineMedian: Double
    package var currentMedian: Double
    package var percent: Double

    package init(name: String, baselineMedian: Double, currentMedian: Double, percent: Double) {
        self.name = name
        self.baselineMedian = baselineMedian
        self.currentMedian = currentMedian
        self.percent = percent
    }
}

/// Median deltas for benchmarks present in both reports, in the order of `current`.
package func compare(baseline: Report, current: Report) -> [Delta] {
    let baselineMedians = Dictionary(
        baseline.entries.map { ($0.name, $0.summary.median) },
        uniquingKeysWith: { first, _ in first }
    )

    return current.entries.compactMap { entry in
        guard let old = baselineMedians[entry.name], old > 0 else {
            return nil
        }

        let new = entry.summary.median

        return Delta(name: entry.name, baselineMedian: old, currentMedian: new, percent: (new - old) / old * 100)
    }
}

package func renderTable(_ report: Report) -> String {
    let header = "\(report.workload) @ \(report.revision)\n"
        + row(["benchmark", "n", "min ms", "median ms", "p90 ms", "max ms"])

    let rows = report.entries.map { entry in
        row([
            entry.name,
            String(entry.iterations),
            milliseconds(entry.summary.min),
            milliseconds(entry.summary.median),
            milliseconds(entry.summary.p90),
            milliseconds(entry.summary.max),
        ])
    }

    return ([header] + rows).joined(separator: "\n")
}

package func renderComparison(_ deltas: [Delta]) -> String {
    let header = row(["benchmark", "", "base ms", "now ms", "delta", ""])

    let rows = deltas.map { delta in
        row([
            delta.name,
            "",
            milliseconds(delta.baselineMedian),
            milliseconds(delta.currentMedian),
            String(format: "%+.1f%%", delta.percent),
            "",
        ])
    }

    return ([header] + rows).joined(separator: "\n")
}

private func milliseconds(_ seconds: Double) -> String {
    String(format: "%.2f", seconds * 1000)
}

private func row(_ columns: [String]) -> String {
    let widths = [24, 4, 12, 12, 12, 12]

    return zip(columns, widths)
        .map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
        .joined(separator: " ")
}
