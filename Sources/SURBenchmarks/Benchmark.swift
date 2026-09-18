import SURBenchmarkSupport

struct Benchmark {
    let name: String
    let run: () async throws -> Void

    init(_ name: String, run: @escaping () async throws -> Void) {
        self.name = name
        self.run = run
    }
}

/// Timed samples in seconds. Stops early once `budget` is spent, but always takes one sample;
/// a slow warmup run ends the warmup.
func measure(_ benchmark: Benchmark, warmup: Int, iterations: Int, budget: Duration) async throws -> [Double] {
    let clock = ContinuousClock()

    for _ in 0..<warmup {
        let elapsed = try await clock.measure { try await benchmark.run() }

        if elapsed > budget / 2 {
            break
        }
    }

    var samples: [Double] = []
    var total: Duration = .zero

    while samples.count < iterations && (samples.isEmpty || total < budget) {
        let elapsed = try await clock.measure { try await benchmark.run() }

        samples.append(seconds(elapsed))
        total += elapsed
    }

    return samples
}
