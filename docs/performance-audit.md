# Performance audit — 2026-09-18, measured at revision 481667f

## Results (F1–F3 applied, revision 9bfc500)

Measured with the same harness against the baseline JSON (`--compare`), medians:

| benchmark | medium before | medium after | production app before | production app after |
|---|---|---|---|---|
| analyze | 25 396.5 ms | 3.9 ms | 3 542.0 ms | 2.7 ms |
| fs.discovery | 1 337.2 ms | 280.6 ms | 1 782.8 ms | 328.3 ms |
| e2e | 26 559.8 ms | 376.0 ms | 5 333.9 ms | 451.0 ms |

e2e: **×70 on medium, ×11.8 on the production app.** Every other phase moved within noise.
Behavior check: the full `sur` output on the production app (all targets) is line-for-line
identical before and after, up to the order of targets, which comes from `XcodeProj` and was
never stable; the synthetic oracle test (which does contain unused assets) passes unchanged.

After the change the production app run splits roughly into discovery 73 %, Swift parsing
22 %, xibs 5 % — F4–F6 are now the candidates, in that order.

## Summary

Two functions account for ~98 % of the run time of `sur` on every workload measured:

| | production app | synthetic medium | synthetic large |
|---|---|---|---|
| `unusedResources` (matching) | 66 % | 96 % | 99 % |
| file discovery | 33 % | 5 % | 1 % |
| everything else (project load, Swift parsing, xib parsing) | 2 % | < 1 % | < 1 % |

Matching is O(resources × usages) and compiles a regular expression or rebuilds a
`SwiftIdentifier` for every pair; discovery walks the same directory tree nine times. Both
are fixable without changing behavior, and both are already isolated as functions with tests
and dedicated benchmarks. Estimated effect of the first three fixes (an estimate, to be
confirmed with `--compare`): **~5.3 s → roughly 0.5 s on the production app, ~26 s → about a
second on the medium fixture, ~10.5 min → seconds on the large one.**

Swift parsing and our syntax visitors — where most of the code lives — are 2 % of the run and
not worth optimizing now.

## Method

- Machine: Apple M4, 10 cores, macOS 27.0, AC power. Toolchain: Swift 6.4, release build.
- In-process phases: `swift run -c release SURBenchmarks --size <small|medium|large>` and
  `--project <xcodeproj> --target <app target>`; 2 warmup + 10 measured iterations, stopping
  early after a 60 s budget per benchmark (so slow phases have fewer samples, see `n`).
  Large was run with `--iterations 1 --warmup 0`: one sample per phase is enough when a phase
  takes ten minutes.
- Binary end to end: `Scripts/bench-e2e.sh` (plain loop; hyperfine was not installed).
- Profile: `sample <pid> 30` attached to `SURBenchmarks --filter e2e` on the production app.
  Used only for the breakdown *inside* a phase; shares *between* phases come from the
  benchmarks.
- Noise: a second medium run differed from the baseline by −3.6 % … +0.7 % on every phase
  longer than 100 ms. Phases under ~50 ms (and the parallel parse, which depends on
  scheduling) moved by up to 8 %. Threshold used below: 5 % for long phases, 10 % for short.
- Workloads: synthetic fixtures are generated deterministically by `makeFixturePlan`; an
  oracle test asserts that `sur` reports exactly the assets the plan leaves unreferenced.
  The real workload is a production iOS app: 3 025 Swift files, 4 asset catalogs, 143
  xibs/storyboards, 766 resources, 3 661 collected usages, mostly file-system-synchronized
  groups.

## Baseline

Milliseconds.

**synthetic small** — 100 Swift files, 200 resources, 920 usages

| benchmark | n | min | median | p90 | max |
|---|---|---|---|---|---|
| xcodeproj.load | 10 | 0.61 | 0.63 | 0.66 | 0.66 |
| fs.discovery | 10 | 139.89 | 142.74 | 144.41 | 148.53 |
| swift.parse.serial | 10 | 15.77 | 16.11 | 16.37 | 16.85 |
| swift.parse.parallel | 10 | 3.32 | 4.10 | 4.97 | 6.02 |
| xib.parse | 10 | 0.22 | 0.23 | 0.25 | 0.28 |
| analyze | 10 | 235.43 | 240.11 | 242.16 | 245.13 |
| e2e | 10 | 392.22 | 396.76 | 408.78 | 408.94 |

**synthetic medium** — 1 000 Swift files, 2 000 resources, 9 277 usages

| benchmark | n | min | median | p90 | max |
|---|---|---|---|---|---|
| xcodeproj.load | 10 | 1.48 | 1.54 | 1.60 | 1.60 |
| fs.discovery | 10 | 1 278.03 | 1 337.16 | 1 375.88 | 1 420.90 |
| swift.parse.serial | 10 | 151.17 | 154.34 | 163.10 | 180.12 |
| swift.parse.parallel | 10 | 32.68 | 35.29 | 39.17 | 41.35 |
| xib.parse | 10 | 1.92 | 2.20 | 2.21 | 2.22 |
| analyze | 3 | 24 726.48 | 25 396.50 | 25 537.15 | 25 537.15 |
| e2e | 3 | 26 515.76 | 26 559.83 | 26 793.23 | 26 793.23 |

**synthetic large** — 5 000 Swift files, 10 000 resources, 46 401 usages (single sample)

| benchmark | n | value |
|---|---|---|
| xcodeproj.load | 1 | 7.13 |
| fs.discovery | 1 | 6 902.54 |
| swift.parse.serial | 1 | 1 329.81 |
| swift.parse.parallel | 1 | 175.11 |
| xib.parse | 1 | 35.06 |
| analyze | 1 | 631 553.52 |
| e2e | 1 | 639 238.50 |

**production app**

| benchmark | n | min | median | p90 | max |
|---|---|---|---|---|---|
| xcodeproj.load | 10 | 4.27 | 4.31 | 4.36 | 4.55 |
| fs.discovery | 10 | 1 748.39 | 1 782.82 | 1 810.16 | 3 163.14 |
| swift.parse.serial | 10 | 682.32 | 687.61 | 694.83 | 709.22 |
| swift.parse.parallel | 10 | 102.16 | 107.55 | 126.77 | 148.95 |
| xib.parse | 10 | 26.21 | 27.08 | 28.93 | 28.93 |
| analyze | 10 | 3 443.21 | 3 542.02 | 3 564.22 | 3 573.89 |
| e2e | 10 | 5 280.27 | 5 333.91 | 5 380.29 | 5 475.00 |

Release `sur` binary on the production app, 3 runs: 5.59 s, 5.60 s, 5.66 s — process startup
and output add ~0.3 s to the in-process figure.

## Where the time goes

Share of the e2e median (parse = the parallel variant, which is what `sur` runs). Shares can
add up to slightly more than 100 %: the isolated phases ignore `sur.yml` exclusions and cover
everything discovered, while `e2e` honors the exclusions (production app); on the synthetic
fixtures, which have no `sur.yml`, the sub-percent excess is run-to-run noise between phases
measured with different sample counts.

| phase | small | medium | large | production app |
|---|---|---|---|---|
| analyze | 60.5 % | 95.6 % | 98.8 % | 66.4 % |
| fs.discovery | 36.0 % | 5.0 % | 1.1 % | 33.4 % |
| swift.parse.parallel | 1.0 % | 0.1 % | < 0.1 % | 2.0 % |
| xib.parse | 0.1 % | < 0.1 % | < 0.1 % | 0.5 % |
| xcodeproj.load | 0.2 % | < 0.1 % | < 0.1 % | 0.1 % |

Scaling of `analyze`: input ×10 (small → medium) costs ×106; input ×5 (medium → large) costs
×25. That is the quadratic signature. Discovery scales linearly (×9.4, ×5.2).

Inside `analyze` (production app profile, 9 752 samples in `unusedResources`):

- 46 % — `NSRegularExpression(pattern:)`: compiling `^pattern$` for every
  (resource, `.regexp` usage) pair, plus the regex compiled inside every
  `withoutImageAndColor()` call;
- 36 % — `SwiftIdentifier(name:)`, rebuilt for every (resource, `.rswift`/`.generated`
  usage) pair: `components(separatedBy: CharacterSet)` alone is 12 %, the rest is its two
  regex replacements and string bridging;
- ~15 % — regex matching / replacement itself; the comparisons are noise.

Inside `fs.discovery` (9 230 samples): 97 % is `NSAllDescendantPathsEnumerator.nextObject`
(`Path+Utils.swift:43`), i.e. the directory walk itself — `open` on directories is the single
hottest kernel call of the whole process. Filtering, sorting, `Path` concatenation and
`containsDirectory` together are under 3 %.

Inside Swift parsing (3 724 samples across worker threads): 46 % swift-syntax
`Parser.parse`, 34 % `String(contentsOf:)`, ~20 % all of our visitors together
(`FuncCallVisitor` 1.6 %).

## Findings

Sorted by expected gain ÷ risk.

### F1. Matching recomputes per pair what depends on one side only

- **Where:** `Sources/SURCore/Analysis/UnusedResources.swift:19-46`; `String.withoutImageAndColor()` in `Sources/SURCore/Explorer.swift`
- **Evidence:** 46 % + 36 % of `analyze`; `analyze` is 66 % of e2e on the production app, 96–99 % on medium/large.
- **Proposed fix:** keep the function pure, split it into two pure steps.
  1. `ResourceKeys` per resource, computed once: `name`, `rswiftIdentifier = SwiftIdentifier(name:).description`, `generatedIdentifier = rswiftIdentifier.withoutImageAndColor()`. `withoutImageAndColor` uses one file-level compiled regex (as `SwiftIdentifier.swift` already does for its own two).
  2. Compile each distinct `.regexp` pattern once per call (`[String: NSRegularExpression]`), still throwing on an invalid pattern.
- **Expected gain:** removes ~80 % of `analyze` while staying O(R×U): production app ≈ 3.5 s → ≈ 0.7 s; shows on `analyze` and `e2e`.
- **Behavior risk:** low — same comparisons, same order; pinned by `UnusedResourcesTests` (every usage case, order) and the fixture oracle. One edge must be kept deliberately, see "Invalid patterns" under F2.
- **Effort:** S

### F2. Matching is O(resources × usages)

- **Where:** same function.
- **Evidence:** ×106 time for ×10 input; 10.5 min on the large fixture.
- **Important property of the input:** *every* `named:` / `Image("…")` argument becomes a `.regexp` usage, plain literals included (`FuncCallVisitor` appends `.regexp(StringVisitor(...).parse(), kind)`; `UIImage(named: "star")` yields `.regexp("star", .image)`), and literal segments are not escaped. So distinct patterns are *not* few: about a third of the image references in the synthetic fixtures (2 of the 6 reference forms), i.e. about a thousand distinct patterns on medium and several thousand on large after de-duplication. De-duplicating compiled regexes alone would still leave R × patterns in the order of 10⁷ regex matches on large.
- **Proposed fix (on top of F1):** index usages once per kind.
  1. `Set<String>` of `.string` values, of `.rswift` identifiers, of `.generated` identifiers.
  2. Split `.regexp` patterns: a pattern that is pure ASCII and contains no regex metacharacter (`\ ^ $ . | ? * + ( ) [ ] { }`) is equivalent to an exact name and goes into the exact-name set (`^p$` ⇔ `name == p`; restricted to ASCII because `String ==` uses canonical equivalence and `NSRegularExpression` does not; `$` also matches before a trailing line terminator, so the exact path must additionally require that the resource name contains no line terminator — legal on APFS, absurd in practice — and fall back to the regex otherwise). Only the remaining, genuinely dynamic patterns (interpolations, `// image: …` comment patterns) are compiled, once each.
  3. A resource is used iff `names.contains(name) || rswift.contains(rswiftIdentifier) || generated.contains(generatedIdentifier) || dynamicRegexes.contains { matches }` — exact sets first, regexes last. Cost: O(R + U + R × dynamic patterns).
- **Invalid patterns:** today there is no short-circuit, so an invalid pattern (e.g. `UIImage(named: "a(b")`) throws whenever *any* non-excluded resource of that kind exists. With lazy compilation plus short-circuiting it would silently stop throwing when every resource matches an exact set. To preserve behavior: compile all dynamic patterns of a kind eagerly as soon as the first non-excluded resource of that kind is seen. Note that `a(b` contains a metacharacter, so it stays on the regex path and still throws. Add a test before the change: an invalid pattern plus a resource matched by a `.string` usage must still throw (the existing `invalidPattern` test has a single unmatched resource and would not catch the regression).
- **Expected gain:** to be measured. The exact part is linear; what remains is R × dynamic patterns. On the synthetic fixtures there is one dynamic pattern (`imgStep.*`), so `analyze` should fall to milliseconds there; on the production app it depends on how many interpolated names the code base has — count them (`usages` that fail the literal test) as the first step of the change.
- **Behavior risk:** low–medium — membership instead of a count is safe (`usageCount == 0` is all that was ever used), but the literal-pattern shortcut and the invalid-pattern edge above are real semantics that need their own tests (literal with a metacharacter, non-ASCII literal, invalid pattern with all resources matched).
- **Effort:** S–M

### F3. Discovery walks the same tree nine times, catalogs twice

- **Where:** `Sources/SURCore/Discovery/DiscoveredFiles.swift:11-34` (8 resource extensions + `swift`), `:37-58` (`kinds.flatMap` → one walk per kind), `Sources/SURCore/Utils/Path+Utils.swift:36-60`.
- **Evidence:** 33 % of e2e on the production app (1.78 s), 97 % of it inside the enumerator.
- **Proposed fix:** one walk per root that classifies each entry by extension into buckets (`descendants(withExtensions: Set<String>) -> [String: [Path]]`), then assemble `DiscoveredFiles` in today's order (extension order, each bucket sorted). Same for catalogs: one walk collecting `imageset` and `colorset`. Pruning (not descending into `*.xcassets`, `*.icon`, matched `*.imageset` / `*.colorset`) is a separate, optional step with its own semantics: today a catalog nested inside another catalog is still found, `.swift` files inside a catalog are still collected (sources have no xcassets filter), and the `.icon` skip is case-insensitive and applies to resources only.
- **Expected gain:** ≈ ÷9 for groups, ÷2 for catalogs, more with pruning: production app 1.78 s → ≈ 0.2 s; shows on `fs.discovery` and `e2e`.
- **Behavior risk:** low for the single walk — `DiscoveryTests` pins order and filtering. Medium for pruning: each of the three cases above needs a test first, or pruning must be limited to matched `*.imageset` / `*.colorset` directories, which is always safe.
- **Effort:** S (single walk) / M (with pruning)

### F4. A faster enumerator

- **Where:** `Path+Utils.swift:37` — `FileManager.enumerator(atPath:)`.
- **Evidence:** after F3 the remaining ~0.2 s is still all enumerator; `open`/`getattrlist`/`lstat` dominate.
- **Proposed fix:** `enumerator(at:includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])` (bulk attribute fetch, hidden-file rule built in) — or leave as is.
- **Expected gain:** uncertain, maybe ×1.5–2 of what is left after F3 (≈ 0.1 s). Measure before keeping.
- **Behavior risk:** medium — hidden-entry semantics and the "called on a file, `skipDescendants()` skips the rest of the parent" workaround must be re-verified; `UtilsTests` covers part of it.
- **Effort:** S, but only worth doing if the benchmark shows > 10 %.

### F5. Xibs are parsed sequentially

- **Where:** `Explorer.explore(xib:)` via `explore(resources:)`.
- **Evidence:** `xib.parse` 27 ms = 0.5 % of e2e today; after F1–F3 it becomes ≈ 5 % of a 0.5 s run.
- **Proposed fix:** collect xib paths and parse them in the same task group style as Swift files (results sorted by path for determinism).
- **Expected gain:** ≈ 20 ms on the production app. Only meaningful after F1–F3.
- **Behavior risk:** low (usage order changes, the result set does not).
- **Effort:** S

### F6. `String(contentsOf:)` is a third of parse time

- **Where:** `Sources/SURCore/Parsers/SwiftParser.swift:46`.
- **Evidence:** 34 % of parse-phase samples; parse is 2 % of e2e.
- **Proposed fix:** `String(contentsOf: path, encoding: .utf8)` (skips encoding sniffing), falling back to the sniffing initializer on failure.
- **Expected gain:** ≈ 30 ms of CPU spread over workers, ≈ 10 ms wall. Do it only after F1–F3, when parse becomes ~20 % of the run.
- **Behavior risk:** low with the fallback.
- **Effort:** S

### Side finding (not performance): nondeterministic resource order

`assetResources` iterates `kinds: Set<ExploreKind>`, whose order changes between runs, so the
order of reported unused resources can differ run to run. Iterating `ExploreKind.allCases`
filtered by the set makes output stable. Worth fixing together with F3 since the same lines
are touched.

## Rejected hypotheses

| Hypothesis | Measured | Verdict |
|---|---|---|
| One `FuncCallVisitor` per kind per call expression is expensive | 1.6 % of parse-phase samples → ≈ 0.03 % of e2e | irrelevant |
| Nested visitors (`ReturnVisitor`, `BareMemberVisitor`, `MemberVisitor`) re-walk subtrees | all of our visitors together ≈ 20 % of parse → ≈ 0.4 % of e2e | irrelevant now |
| `FuncCallVisitor.matchComment` / `matchesSkip` compile a regex per trivia piece | not visible in the profile (only reached for `named:` arguments) | irrelevant |
| `StringVisitor` folds operators per sequence expression | 2 samples of 19 175 | irrelevant |
| `excludedSources.contains` / `excludedResources.contains` on arrays, `SwiftKeywords` array | not visible in the profile | irrelevant (F2 removes the inner-loop one anyway) |
| Actor hops on `Storage` | 1 sample | irrelevant |
| `XcodeProj(path:)` is a large fixed floor | 4.3 ms on a 3 000-file project | irrelevant |
| `InitArgumentResolver` cross-file resolution | 1 sample | irrelevant |

These become worth a second look only if the run time drops to ~100 ms and parsing becomes
the dominant phase.

## Recommended order

1. **F1 + F2** together (one change to one pure function, guarded by `UnusedResourcesTests` and the oracle). First add the missing tests (invalid pattern with matched resources, literal vs. metacharacter vs. non-ASCII patterns) and count dynamic patterns on the production app. Then re-run `--size medium --compare` and the production app.
2. **F3** single-walk discovery, plus the ordering side finding.
3. Re-measure. Rough expectation for the production app: e2e around half a second, split mainly between discovery and parsing — an estimate, not a promise; the benchmark decides.
4. Then decide on **F4–F6** from the new numbers; each must show > 10 % on its benchmark to be kept.
