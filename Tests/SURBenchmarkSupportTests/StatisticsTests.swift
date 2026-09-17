import Testing

@testable import SURBenchmarkSupport

@Suite("Statistics")
struct StatisticsTests {
    @Test("Empty input has no summary")
    func empty() {
        #expect(summarize([]) == nil)
    }

    @Test("Odd count: median is the middle sample")
    func odd() {
        #expect(summarize([3, 1, 2]) == Summary(min: 1, median: 2, p90: 3, max: 3))
    }

    @Test("Even count: median is the mean of the two middle samples")
    func even() {
        #expect(summarize([4, 1, 3, 2])?.median == 2.5)
    }

    @Test("p90 is the nearest-rank percentile")
    func p90() {
        #expect(summarize((1...10).map(Double.init))?.p90 == 9)
    }

    @Test("Duration converts to seconds")
    func duration() {
        #expect(seconds(.milliseconds(1500)) == 1.5)
    }

    @Test("Seeded generator is deterministic and seed-sensitive")
    func generator() {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        var other = SeededGenerator(seed: 43)

        let a = (0..<8).map { _ in first.next() }
        let b = (0..<8).map { _ in second.next() }
        let c = (0..<8).map { _ in other.next() }

        #expect(a == b)
        #expect(a != c)
    }
}
