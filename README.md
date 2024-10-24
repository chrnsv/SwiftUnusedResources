# SUR

`sur` is commandline tool that helps you to keep image resources of Xcode project on track.

## Installation

### Using [Mint](https://github.com/yonaskolb/Mint)

```shell
mint install mugabe/SwiftUnusedResources
```

### Compile from source

```bash
> git clone https://github.com/mugabe/SwiftUnusedResources.git
> cd SwiftUnusedResources
> swift build -c release
> cp .build/release/sur /usr/local/bin/sur
```

### Cocoapods

```ruby
pod 'SwiftUnusedResources'
```

`sur` will be installed at `${PODS_ROOT}/SwiftUnusedResources/sur`

### Xcode Package Dependency

Use the following link to add SwiftLint as a Package Dependency to an Xcode
project:

```bash
git@github.com:mugabe/SwiftUnusedResources.git
```

## Usage

Just type `sur` under your project's path

```shell
> sur
```

or

## Xcode integration

### Cocoapods installation

Add a `Run Script` phase to each target.

```shell
"${PODS_ROOT}/SwiftUnusedResources/sur"
```

### SPM installation

Add the `SURBuildToolPlugin` to the `Run Build Tool Plug-ins` phase of the `Build Phases` for the each target.

On every project build `sur` will throw warnings about unused images.

### When running on CI

Add a script with the content: 

```shell
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
```

## How it works

`sur` finds images and colors included in the target, and then detects if they are used by the xibs, storyboards, and swift files.
`sur` will search for `UIImage(named: <image>)` (in UIKit and WatchKit files), `Image(<image>)` (in SwiftUI files), `#imageLiteral(<image>)`, `R.image.<image>()`, and will try to guess best pattern to match images even with partial names. It also supports generated assets such as `Image(.<image>)` and `Image.<image>` but currently does not support the `.<image>` declaration.

```swift
// Any part of the name that sur couldn't guess will be replaced with `*`.

UIImage(named: "icon" + size) 
// all icon* resources whould be marked as used

Image("some\(value)image")
// all some*image resources would be marked


// Ternary operators should work well

Image("button" + (enabled ? "Normal" : "Gray"))
// only buttonNormal and buttonGray would be marked
```

However, if no strings were used in image creation `sur` will fail with guess.
In this case (as in case if guessed pattern too wide) you can specify regexp pattern on your own by doc comment.

```swift
// image: icon(Small|Large)
UIImage(named: "icon" + someting())

// image: frame\d+
Image("frame\(count)")

// image: (apple|banana|whiskey)
Image(image)
```

## Configuration

You can place `sur.yml` to the root of your project to configure your rules. Example configuration:

```yaml
exclude:
  sources:
    - <path to the source file>
  resources:
    - <name of resource>
  assets:
    - <name of xcassets>
```
