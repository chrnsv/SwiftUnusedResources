import Foundation
import Testing

@testable import SURBenchmarkSupport

@Suite("Report")
struct ReportTests {
    private func report(_ medians: [String: Double]) -> Report {
        Report(
            revision: "abc1234",
            workload: "synthetic-small",
            date: Date(timeIntervalSince1970: 0),
            entries: medians.sorted { $0.key < $1.key }.map {
                .init(name: $0.key, iterations: 10, summary: Summary(min: $0.value, median: $0.value, p90: $0.value, max: $0.value))
            }
        )
    }

    @Test("Compares medians of benchmarks present in both reports, in current order")
    func comparison() {
        let deltas = compare(
            baseline: report(["analyze": 2.0, "gone": 1.0]),
            current: report(["analyze": 1.0, "new": 1.0])
        )

        #expect(deltas == [Delta(name: "analyze", baselineMedian: 2.0, currentMedian: 1.0, percent: -50)])
    }

    @Test("Survives a JSON round trip")
    func roundTrip() throws {
        let original = report(["e2e": 0.25])
        let decoded = try JSONDecoder().decode(Report.self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
    }

    @Test("Table lists every benchmark with millisecond values")
    func table() {
        let text = renderTable(report(["e2e": 0.25]))

        #expect(text.contains("e2e"))
        #expect(text.contains("250.00"))
    }

    @Test("Comparison renders a signed percentage")
    func comparisonText() {
        let text = renderComparison([Delta(name: "analyze", baselineMedian: 2, currentMedian: 1, percent: -50)])

        #expect(text.contains("analyze"))
        #expect(text.contains("-50.0%"))
    }
}
