import PathKit
import SURCore
import XcodeProj

func benchmarks(for workload: Workload) -> [Benchmark] {
    let kinds: Set<ExploreKind> = [.image, .color]
    let parser = SwiftParser(kinds: kinds)

    return [
        Benchmark("xcodeproj.load") {
            _ = try XcodeProj(path: workload.projectPath)
        },
        Benchmark("fs.discovery") {
            for root in workload.groupRoots {
                _ = discoverFiles(inSynchronizedGroup: root)
            }

            for catalog in workload.catalogs {
                _ = assetResources(in: catalog, kinds: kinds, excludedAssets: [])
            }
        },
        Benchmark("swift.parse.serial") {
            for url in workload.swiftFiles {
                _ = try parser.parseDetailed(url)
            }
        },
        Benchmark("swift.parse.parallel") {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for url in workload.swiftFiles {
                    group.addTask {
                        _ = try parser.parseDetailed(url)
                    }
                }

                try await group.waitForAll()
            }
        },
        Benchmark("xib.parse") {
            for xib in workload.xibs {
                _ = try? XibParser().parse(xib)
            }
        },
        Benchmark("analyze") {
            _ = try unusedResources(in: workload.resources, usages: workload.usages, excluding: [])
        },
        Benchmark("e2e") {
            let explorer = try Explorer(
                projectPath: workload.projectPath,
                sourceRoot: workload.sourceRoot,
                target: workload.target,
                showWarnings: false,
                quiet: true
            )

            try await explorer.explore()
        },
    ]
}
