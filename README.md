# SUR

`sur` is a command-line tool that finds unused images and colors in an Xcode project: asset catalog contents as well as standalone image files (`png`, `jpg`, `pdf`, `gif`, `svg`).

## Installation

### Using [Mint](https://github.com/yonaskolb/Mint)

```shell
mint install mugabe/SwiftUnusedResources
```

### Using [mise](https://mise.jdx.dev)

```shell
# install globally
mise use -g github:mugabe/SwiftUnusedResources

# or add it to the current project
mise use github:mugabe/SwiftUnusedResources
```

Alternatively, add it to your project's `mise.toml` by hand and run `mise install`:

```toml
[tools]
"github:mugabe/SwiftUnusedResources" = "latest"
```

Replace `latest` with a release tag to pin a specific version.

mise downloads the prebuilt binary from GitHub releases, so no Swift toolchain is needed.
Releases ship binaries for macOS on Apple silicon and for Linux on x86_64 and arm64; mise
picks the right one on its own, so no extra configuration is required.

The Linux binaries link the Swift runtime statically and are built on Ubuntu 22.04, so they
run on any distribution with glibc 2.35 or newer — Ubuntu 22.04, Debian 12 and anything more
recent. The only shared library they need is `libxml2`. Most distributions and CI images
already have it; minimal containers do not:

```shell
apt-get install -y libxml2
```

### Compile from source

```shell
git clone https://github.com/mugabe/SwiftUnusedResources.git
cd SwiftUnusedResources
swift build -c release
cp .build/release/sur /usr/local/bin/sur
```

`sur` builds and runs on Linux as well as macOS; Swift 6.3 or newer is required.
Note that the `SURBuildToolPlugin` is only useful from Xcode.

### Xcode Package Dependency

Add SwiftUnusedResources as a Package Dependency to your Xcode project using the following link:

```
https://github.com/mugabe/SwiftUnusedResources.git
```

## Usage

Run `sur` in the directory that contains your `.xcodeproj`:

```shell
sur
```

or point it at a project and a target explicitly:

```shell
sur --project path/to/App.xcodeproj --target App
```

| Option | Description |
| --- | --- |
| `-p`, `--project` | Path to the `.xcodeproj`. Defaults to the one in the current directory. |
| `-t`, `--target` | Target to check. All targets are checked when omitted. |
| `-v`, `--version` | Show the version. |

## Xcode integration

Add the `SURBuildToolPlugin` to the `Run Build Tool Plug-ins` phase of the `Build Phases` of each target.

On every project build `sur` will emit warnings about unused images and colors.

### When running on CI

Xcode asks to trust package plugins interactively, so disable the validation on CI:

```shell
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
```

## How it works

`sur` finds the images and colors included in the target, and then detects whether they are used by xibs, storyboards, and Swift files.

In Swift files `sur` looks for:

- `UIImage(named: <image>)` and `UIColor(named: <color>)` (UIKit and WatchKit), `Image(<image>)` and `Color(<color>)` (SwiftUI);
- `#imageLiteral(<image>)`;
- `R.image.<image>()` and `R.color.<color>()`;
- generated asset symbols: `Image(.<image>)`, `ImageResource.<image>`, `UIColor.<color>` and so on. A bare `.<image>` is resolved
  where the type is known: type-annotated bindings, return values of functions and computed properties, and arguments of the
  known SwiftUI modifiers, UIKit setters and properties (see [Custom symbols](#custom-symbols)).

When a name is built dynamically, `sur` tries to guess the best pattern to match resources even with partial names:

```swift
// Any part of the name that sur couldn't guess will be replaced with `*`.

UIImage(named: "icon" + size)
// all icon* resources would be marked as used

Image("some\(value)image")
// all some*image resources would be marked

// Ternary operators work well

Image("button" + (enabled ? "Normal" : "Gray"))
// only buttonNormal and buttonGray would be marked
```

However, if no string literals are involved, `sur` can't guess the name and emits a warning.
In this case (or if the guessed pattern is too wide) you can specify a regexp pattern yourself with an `image:` or `color:` comment:

```swift
// image: icon(Small|Large)
UIImage(named: "icon" + something())

// image: frame\d+
Image("frame\(count)")

// image: (apple|banana|whiskey)
Image(image)

// color: accent(Light|Dark)
Color(colorName)
```

To just silence the warning without marking anything as used, add a `sur: skip` comment:

```swift
// sur: skip
Image(name)
```

## Configuration

Place a `sur.yml` in the root of your project to configure the tool. Example configuration:

```yaml
kinds:          # resource kinds to check; both are checked by default
  - image
  - color
exclude:
  sources:      # Swift files that should not be parsed, relative to the project root
    - <path to the source file>
  resources:    # resources that should never be reported
    - <name of resource>
  assets:       # asset catalogs that should be ignored entirely
    - <name of xcassets>
```

### Custom symbols

The tool ships with a built-in list of SwiftUI modifiers, UIKit setters
(`.foregroundColor(.brand)`, `setImage(.star, for: .normal)`, …) and UIKit properties
(`label.textColor = .brand`, `imageView.image = .star`, …) whose arguments are treated as
generated asset symbols. If your project uses custom APIs in the same style, extend the
lists in `sur.yml` so assets passed to them are not reported as unused:

```yaml
symbols:
  calls:        # member calls: view.neonGlow(.brandPink), button.setCustomIcon(.star, for: .normal)
    color:
      - neonGlow
    image:
      - setCustomIcon
  properties:   # property assignments: theme.brandColor = .accent
    color:
      - brandColor
```

Only unlabeled arguments and arguments labeled `color:` of listed calls are collected, so
control labels (`for:`, `alignment:`, …) are never mistaken for assets.

## Migrating from R.swift

`sur r-to-xcode` rewrites R.swift usages to the symbols Xcode generates for string catalogs and asset catalogs:

```shell
# preview the changes without touching any files
sur r-to-xcode path/to/App.xcodeproj --target App --dry-run

# rewrite only assets (or only strings with --strings); both are rewritten by default
sur r-to-xcode path/to/App.xcodeproj --assets --exclude Sources/Generated/R.generated.swift
```

`--exclude` paths are absolute or relative to the source root (the directory containing the `.xcodeproj`, unless `--source-root` is given).
Run `sur r-to-xcode --help` for the full list of options.

## Benchmarks

`SURBenchmarks` measures each phase of the pipeline in-process. Always build it in release.

```bash
# synthetic fixture (small | medium | large)
swift run -c release SURBenchmarks --size medium --json .benchmarks/baseline.json

# after a change
swift run -c release SURBenchmarks --size medium --compare .benchmarks/baseline.json

# a real project
swift run -c release SURBenchmarks --project /path/to/App.xcodeproj --target App
```

Benchmarks: `xcodeproj.load`, `fs.discovery`, `swift.parse.serial`, `swift.parse.parallel`,
`xib.parse`, `analyze`, `e2e`. Each one stops early after `--max-seconds` (default 60) but always
takes at least one sample. `fs.discovery`, `swift.parse.*` and `xib.parse` run over every
file found, ignoring `sur.yml`; `analyze` runs on the resources and usages a real `Explorer` pass
collected, so it (like `e2e`) honors `sur.yml`.
Treat median deltas under ~5 % as noise. `Scripts/bench-e2e.sh` times the `sur` binary itself.

## Releasing

Releases are built entirely on CI, so every published version carries binaries for all
supported platforms:

```shell
mise run release 0.5.0
```

That triggers the `Release` workflow, which builds `sur` on a macOS runner and on native
x86_64 and arm64 Linux runners, packages the results, writes the artifact bundle URL and
checksum into `Package.swift`, commits, tags and publishes the release.

The workflow drives the same mise tasks that are available locally:

| Task | Purpose |
| --- | --- |
| `set-version <version>` | Writes the version constant into `SUR.swift`. |
| `stage-binary` | Builds the release binary for the host platform into `.release/<slot>/`. |
| `artifactbundle <version>` | Packs the macOS binary as `sur-<version>.artifactbundle.zip`. |
| `archives <version>` | Packs every staged binary as `sur-<version>-<slot>.tar.gz`. |
| `publish <version>` | Writes the URL and checksum, commits, tags and uploads every asset. |

A release therefore carries two kinds of assets, and they are not interchangeable:

- **`sur-<version>.artifactbundle.zip`** backs the `SURBinary` binary target behind
  `SURBuildToolPlugin`. The plugin only ever runs from Xcode, so the bundle holds the macOS
  binary alone rather than growing with every platform.
- **`sur-<version>-<os>-<arch>.tar.gz`** is what installers consume. mise scores assets on
  the os and arch tokens in their names, so it cannot match the bundle — its name carries
  none — and needs these archives on macOS just as much as on Linux.

`Package.swift` keeps pointing at the previous release until `publish` runs: SwiftPM
downloads binary artifacts while resolving, so repointing `SURBinary` any earlier would
break the builds that produce the very bundle it refers to.

To check the Linux build without waiting for CI, run it in a container
([Apple's `container`](https://github.com/apple/container)):

```shell
mise run linux-build   # release binary
mise run linux-test    # full test suite
```
