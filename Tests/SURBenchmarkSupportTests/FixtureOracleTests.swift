import PathKit
import Testing

@testable import SURBenchmarkSupport
@testable import SURCore

@Suite("Synthetic fixture is a correctness oracle")
struct FixtureOracleTests {
    @Test("Explorer reports exactly the assets the plan left unreferenced")
    func oracle() async throws {
        let plan = makeFixturePlan(.small)
        let fixture = try writeFixture(plan, into: makeTemporaryFixtureRoot())
        defer { fixture.remove() }

        let explorer = try Explorer(
            projectPath: fixture.projectPath,
            sourceRoot: fixture.root,
            target: FixturePlan.targetName,
            showWarnings: false,
            quiet: true
        )
        try await explorer.explore()

        let unused = Set(await explorer.storage.unused.map(\.name))

        #expect(unused == plan.expectedUnused)
    }
}
