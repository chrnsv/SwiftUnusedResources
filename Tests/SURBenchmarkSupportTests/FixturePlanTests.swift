import Testing

@testable import SURBenchmarkSupport

@Suite("Fixture plan")
struct FixturePlanTests {
    @Test("Same spec, same plan")
    func deterministic() {
        let first = makeFixturePlan(.small)
        let second = makeFixturePlan(.small)

        #expect(first == second)
    }

    @Test("Different seed, different plan")
    func seedSensitive() {
        var other = FixtureSpec.small
        other.seed += 1

        #expect(makeFixturePlan(.small) != makeFixturePlan(other))
    }

    @Test("File counts follow the spec")
    func counts() {
        let spec = FixtureSpec.small
        let plan = makeFixturePlan(spec)

        func count(_ suffix: String) -> Int {
            plan.files.count { $0.path.hasSuffix(suffix) }
        }

        #expect(count(".swift") == spec.swiftFiles)
        #expect(count(".imageset/Contents.json") == spec.imageSets)
        #expect(count(".colorset/Contents.json") == spec.colorSets)
        #expect(count(".png") == spec.looseImages)
        #expect(count(".xib") == spec.xibs)
    }

    @Test("Roughly the requested share of assets is unused, and none of them is mentioned anywhere")
    func unused() {
        let spec = FixtureSpec.small
        let plan = makeFixturePlan(spec)
        let total = spec.imageSets + spec.colorSets + spec.looseImages
        let share = Double(plan.expectedUnused.count) / Double(total)

        #expect(share > 0.05 && share < 0.30)

        let text = plan.files
            .filter { $0.path.hasSuffix(".swift") || $0.path.hasSuffix(".xib") }
            .map(\.contents)
            .joined(separator: "\n")

        for name in plan.expectedUnused {
            // Match the whole identifier: `imgStar1` must not be "found" inside `imgStar12`.
            let mentioned = text.contains("\"\(name)\"") || text.contains(".\(name)\n")
                || text.contains(".\(name))") || text.contains(".\(name),") || text.contains(".\(name)(")
            #expect(!mentioned, "\(name) is referenced but expected unused")
        }
    }

    @Test("Size names resolve")
    func sizeNames() {
        #expect(FixtureSpec(sizeName: "medium") == .medium)
        #expect(FixtureSpec(sizeName: "huge") == nil)
    }
}
