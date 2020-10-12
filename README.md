## SUR

`sur` is commandline tool that helps you to keep image resources of Xcode project on track.

### Installation

#### Using [Mint](https://github.com/yonaskolb/Mint):
```bash
mint install mugabe/SwiftUnusedResources
```

#### Compile from source

```bash
> git clone https://github.com/mugabe/SwiftUnusedResources.git
> cd SwiftUnusedResources
> swift build -c release
> cp .build/release/sur /usr/local/bin/sur
```

#### Cocoapods

```
pod 'SwiftUnusedResources'
```

`sur` will be installed at `${PODS_ROOT}/SwiftUnusedResources/sur`

### Usage

Just type `sur` under your project's path
```shell
> sur
```

or

### Xcode integration

Add a "Run Script" phase to each target. 

```
"${PODS_ROOT}/SwiftUnusedResources/sur"
```

On every project build `sur` will throw warnings about unused images.

## How it works

`sur` finds images included in the target, and then detects if they are used by the xibs, storyboards, and swift files.
`sur` will search for `UIImage(named: <image>)` (in UIKit and WatchKit files), `Image(<image>)` (in SwiftUI files), `#imageLiteral(<image>)`, `R.image.<image>()`, and will try to guess best pattern to match images even with partial names.

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
/// image: icon(Small|Large)
UIImage(named: "icon" + someting())

/// image: frame\d+
Image("frame\(count)")

/// image: (apple|banana|whiskey)
Image(image)
```
