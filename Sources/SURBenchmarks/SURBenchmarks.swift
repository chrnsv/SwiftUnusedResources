import ArgumentParser
import Foundation
import PathKit
import SURBenchmarkSupport

@main
struct SURBenchmarks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "SURBenchmarks",
        abstract: "Benchmarks of the sur pipeline on a synthetic fixture or a real project"
    )

    @Option(help: "Synthetic fixture size: small, medium or large.")
    var size = "medium"

    @Option(help: "Measured iterations per benchmark.")
    var iterations = 10

    @Option(help: "Warmup iterations per benchmark.")
    var warmup = 2

    @Option(help: "Time budget per benchmark, seconds. At least one sample is always taken.")
    var maxSeconds = 60

    @Option(help: "Run only benchmarks whose name contains this substring.")
    var filter: String?

    @Option(help: "Write the report as JSON to this path.")
    var json: String?

    @Option(help: "Compare against a previously written JSON report.")
    var compare: String?

    @Option(help: "Benchmark a real .xcodeproj instead of the synthetic fixture.", transform: { Path($0).absolute() })
    var project: Path?

    @Option(help: "Target of the real project. Recommended: the analyze phase uses the last processed target.")
    var target: String?

    func validate() throws {
        guard iterations >= 1 else {
            throw ValidationError("--iterations must be at least 1")
        }

        guard warmup >= 0 else {
            throw ValidationError("--warmup must not be negative")
        }

        guard maxSeconds >= 1 else {
            throw ValidationError("--max-seconds must be at least 1")
        }
    }

    func run() async throws {
        #if DEBUG
        print("warning: debug build — numbers are not meaningful, use `swift run -c release SURBenchmarks`")
        #endif

        var cleanup: () -> Void = {}
        defer { cleanup() }

        let workload: Workload

        if let project {
            workload = try await loadWorkload(label: "real", projectPath: project, target: target)
        }
        else {
            guard let spec = FixtureSpec(sizeName: size) else {
                throw ValidationError("Unknown size '\(size)', expected small, medium or large")
            }

            let fixture = try writeFixture(makeFixturePlan(spec), into: makeTemporaryFixtureRoot())
            cleanup = fixture.remove

            workload = try await loadWorkload(
                label: "synthetic-\(size)",
                projectPath: fixture.projectPath,
                target: FixturePlan.targetName
            )
        }

        print(workload.description)

        var entries: [Report.Entry] = []

        for benchmark in benchmarks(for: workload) where filter.map({ benchmark.name.contains($0) }) ?? true {
            print("  running \(benchmark.name)…")

            let samples = try await measure(
                benchmark,
                warmup: warmup,
                iterations: iterations,
                budget: .seconds(maxSeconds)
            )

            if let summary = summarize(samples) {
                entries.append(.init(name: benchmark.name, iterations: samples.count, summary: summary))
            }
        }

        let report = Report(revision: gitRevision(), workload: workload.label, date: Date(), entries: entries)

        print(renderTable(report))

        if let json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let path = Path(json)
            try path.parent().mkpath()
            try path.write(encoder.encode(report))
        }

        if let compare {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let baseline = try decoder.decode(Report.self, from: Path(compare).read())

            print("\nvs \(baseline.workload) @ \(baseline.revision)")
            print(renderComparison(SURBenchmarkSupport.compare(baseline: baseline, current: report)))
        }
    }
}

private func gitRevision() -> String {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "rev-parse", "--short", "HEAD"]
    process.standardOutput = pipe
    process.standardError = Pipe()

    guard (try? process.run()) != nil else {
        return "unknown"
    }

    process.waitUntilExit()

    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let revision = output.trimmingCharacters(in: .whitespacesAndNewlines)

    return revision.isEmpty ? "unknown" : revision
}
