package struct FixturePlan: Equatable, Sendable {
    package static let targetName = "App"

    /// Every file of the fixture, relative to its root (the project file is written separately).
    package var files: [File]
    package var synchronizedGroups: [String]
    package var classicSources: [String]
    package var classicResources: [String]
    /// Names of the assets no source or xib refers to — what `sur` must report.
    package var expectedUnused: Set<String>

    package struct File: Equatable, Sendable {
        package var path: String
        package var contents: String
    }
}

package func makeFixturePlan(_ spec: FixtureSpec) -> FixturePlan {
    var generator = SeededGenerator(seed: spec.seed)

    let stepFamily = (0..<10).map { "imgStep\($0)" }
    let images = (0..<max(spec.imageSets - stepFamily.count, 0)).map { "img\(word($0))\($0)" } + stepFamily
    let colors = (0..<spec.colorSets).map { "clr\(word($0))\($0)" }
    let loose = (0..<spec.looseImages).map { "imgLoose\($0)" }

    // The step family is referenced only by pattern, so it must never be "unused".
    let unused = Set(
        (images.dropLast(stepFamily.count) + colors + loose)
            .filter { _ in Double.random(in: 0..<1, using: &generator) < spec.unusedShare }
    )

    let usedImages = (images.dropLast(stepFamily.count) + loose).filter { !unused.contains($0) }
    let usedColors = colors.filter { !unused.contains($0) }

    var files: [FixturePlan.File] = []
    var classicSources: [String] = []

    // Asset catalogs: every 10th image set lives in the classic Legacy catalog.
    for (index, name) in images.enumerated() {
        let catalog = index.isMultiple(of: 10) ? "Legacy/Legacy.xcassets" : "App/Resources/Assets.xcassets"
        files.append(.init(path: "\(catalog)/Group\(index / 50)/\(name).imageset/Contents.json", contents: kContentsJSON))
    }

    for (index, name) in colors.enumerated() {
        files.append(.init(
            path: "App/Resources/Assets.xcassets/Colors\(index / 50)/\(name).colorset/Contents.json",
            contents: kContentsJSON
        ))
    }

    for name in loose {
        files.append(.init(path: "App/Images/\(name).png", contents: "fake image bytes"))
    }

    // Sources: used assets are dealt round-robin so each is referenced at least once,
    // plus a few random extra references per file.
    for index in 0..<spec.swiftFiles {
        var fileImages = usedImages.enumerated().filter { $0.offset % spec.swiftFiles == index }.map(\.element)
        var fileColors = usedColors.enumerated().filter { $0.offset % spec.swiftFiles == index }.map(\.element)

        for _ in 0..<3 {
            if let extra = usedImages.randomElement(using: &generator) {
                fileImages.append(extra)
            }

            if let extra = usedColors.randomElement(using: &generator) {
                fileColors.append(extra)
            }
        }

        let source = swiftSource(index: index, images: fileImages, colors: fileColors, usesStepFamily: index.isMultiple(of: 10))

        if index.isMultiple(of: 10) {
            let path = "Legacy/Legacy\(index).swift"
            classicSources.append(path)
            files.append(.init(path: path, contents: source))
        }
        else {
            files.append(.init(path: "App/Sources/Feature\(index / 25)/Screen\(index).swift", contents: source))
        }
    }

    for index in 0..<spec.xibs {
        let image = usedImages.randomElement(using: &generator)
        let color = usedColors.randomElement(using: &generator)

        files.append(.init(path: "App/Views/View\(index).xib", contents: xibSource(image: image, color: color)))
    }

    return FixturePlan(
        files: files,
        synchronizedGroups: ["App"],
        classicSources: classicSources,
        classicResources: ["Legacy/Legacy.xcassets"],
        expectedUnused: unused
    )
}

private let kContentsJSON = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

private func word(_ index: Int) -> String {
    let words = ["Star", "Moon", "Sun", "Leaf", "Wave", "Cloud", "Stone", "River", "Flame", "Frost"]

    return words[index % words.count]
}

/// One way of referencing an image by name; cycled so every detection path gets traffic.
private func imageReference(_ name: String, variant: Int) -> String {
    switch variant % 6 {
    case 0: "        _ = UIImage(named: \"\(name)\")"
    case 1: "        _ = Image(\"\(name)\")"
    case 2: "        _ = Image(.\(name))"
    case 3: "        _ = UIImage(resource: .\(name))"
    case 4: "        _ = R.image.\(name)()"
    default: "        let typed\(variant): ImageResource = .\(name)\n        _ = typed\(variant)"
    }
}

private func colorReference(_ name: String, variant: Int) -> String {
    switch variant % 5 {
    case 0: "        _ = UIColor(named: \"\(name)\")"
    case 1: "        _ = Color(\"\(name)\")"
    case 2: "        _ = Color(.\(name))"
    case 3: "        _ = R.color.\(name)()"
    default: "        let tint\(variant): ColorResource = .\(name)\n        _ = tint\(variant)"
    }
}

private func swiftSource(index: Int, images: [String], colors: [String], usesStepFamily: Bool) -> String {
    let imageLines = images.enumerated().map { imageReference($0.element, variant: $0.offset + index) }
    let colorLines = colors.enumerated().map { colorReference($0.element, variant: $0.offset + index) }
    let stepLine = usesStepFamily ? ["        _ = UIImage(named: \"imgStep\\(step)\")"] : []
    let body = (imageLines + colorLines + stepLine).joined(separator: "\n")

    return """
    import SwiftUI
    import UIKit

    struct Screen\(index)Model {
        let title: String
        let subtitle: String
        let count: Int

        func summary(limit: Int) -> String {
            let parts = [title, subtitle].filter { !$0.isEmpty }
            let joined = parts.joined(separator: " — ")

            return count > limit ? "\\(joined) (\\(count))" : joined
        }
    }

    struct Screen\(index)View: View {
        let model: Screen\(index)Model

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.title).font(.headline)
                Text(model.summary(limit: 3)).font(.subheadline)
            }
            .padding()
        }
    }

    final class Screen\(index)Controller: UIViewController {
        func configure(step: Int) {
    \(body)
        }
    }

    """
}

private func xibSource(image: String?, color: String?) -> String {
    let imageLine = image.map { "        <image name=\"\($0)\" width=\"24\" height=\"24\"/>" } ?? ""
    let colorLine = color.map {
        "        <namedColor name=\"\($0)\">"
            + "<color red=\"1\" green=\"0\" blue=\"0\" alpha=\"1\" colorSpace=\"custom\" customColorSpace=\"sRGB\"/>"
            + "</namedColor>"
    } ?? ""

    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0">
        <objects>
            <view contentMode="scaleToFill" id="iN0-l3-epB"/>
        </objects>
        <resources>
    \(imageLine)
    \(colorLine)
        </resources>
    </document>

    """
}
