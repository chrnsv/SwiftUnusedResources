import Foundation

extension SourceVisitor {
    /// Modules whose import enables UIKit-style detection.
    static let uiKitModules: Set<String> = ["UIKit", "WatchKit"]

    /// Modules whose import enables SwiftUI-style detection.
    static let swiftUIModules: Set<String> = ["SwiftUI"]

    /// Modules whose types carry generated asset symbols, used to resolve
    /// module-qualified access like `SwiftUI.Image.star` or `UIKit.UIColor.brand`.
    static let assetModules: Set<String> = uiKitModules
        .union(swiftUIModules)
        .union(["DeveloperToolsSupport"])

    /// Class name → kind for every type Xcode extends with generated asset symbol properties.
    static let generatedClassKinds: [String: ExploreKind] = Dictionary(
        uniqueKeysWithValues: ExploreKind.allCases.flatMap { kind in
            kind.generatedClassNames.map { ($0, kind) }
        }
    )

    /// SwiftUI modifiers and UIKit setters whose arguments carry generated asset symbols,
    /// e.g. `.foregroundColor(.brand)` or `button.setImage(.star, for: .normal)`.
    /// Extensible per project via the `symbols.calls` section of sur.yml.
    static let defaultMemberCallKinds: [String: ExploreKind] = [
        "foregroundColor": .color,
        "foregroundStyle": .color,
        "backgroundStyle": .color,
        "tint": .color,
        "accentColor": .color,
        "background": .color,
        "containerBackground": .color,
        "fill": .color,
        "stroke": .color,
        "strokeBorder": .color,
        "border": .color,
        "shadow": .color,
        "listRowBackground": .color,
        "listItemTint": .color,
        "listRowSeparatorTint": .color,
        "listSectionSeparatorTint": .color,
        "toolbarBackground": .color,
        "presentationBackground": .color,
        "underline": .color,
        "strikethrough": .color,
        "setTitleColor": .color,
        "setTitleShadowColor": .color,
        "setImage": .image,
        "setBackgroundImage": .image,
        "setThumbImage": .image,
        "setMinimumTrackImage": .image,
        "setMaximumTrackImage": .image,
        "setIndicatorImage": .image,
        "setCurrentPageIndicatorImage": .image,
    ]

    /// Well-known UIKit color/image properties whose assignment carries generated asset
    /// symbols, e.g. `label.textColor = .brand` or `imageView.image = .star`.
    /// Extensible per project via the `symbols.properties` section of sur.yml.
    static let defaultPropertyKinds: [String: ExploreKind] = [
        "textColor": .color,
        "backgroundColor": .color,
        "tintColor": .color,
        "barTintColor": .color,
        "unselectedItemTintColor": .color,
        "highlightedTextColor": .color,
        "shadowColor": .color,
        "separatorColor": .color,
        "sectionIndexColor": .color,
        "onTintColor": .color,
        "thumbTintColor": .color,
        "progressTintColor": .color,
        "trackTintColor": .color,
        "minimumTrackTintColor": .color,
        "maximumTrackTintColor": .color,
        "pageIndicatorTintColor": .color,
        "currentPageIndicatorTintColor": .color,
        "image": .image,
        "highlightedImage": .image,
        "selectedImage": .image,
        "shadowImage": .image,
        "backgroundImage": .image,
        "selectionIndicatorImage": .image,
        "progressImage": .image,
        "trackImage": .image,
        "onImage": .image,
        "offImage": .image,
        "minimumValueImage": .image,
        "maximumValueImage": .image,
        "preferredIndicatorImage": .image,
        "preferredCurrentPageIndicatorImage": .image,
    ]
}
