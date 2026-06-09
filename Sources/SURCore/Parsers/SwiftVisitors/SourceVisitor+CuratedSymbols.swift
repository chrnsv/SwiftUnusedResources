import Foundation

extension SourceVisitor {
    /// Modules whose types carry generated asset symbols, used to resolve
    /// module-qualified access like `SwiftUI.Image.star` or `UIKit.UIColor.brand`.
    static let assetModules: Set<String> = ["SwiftUI", "UIKit", "WatchKit", "DeveloperToolsSupport"]

    /// SwiftUI modifiers and UIKit setters whose arguments carry generated asset symbols,
    /// e.g. `.foregroundColor(.brand)` or `button.setImage(.star, for: .normal)`.
    static let memberCallKinds: [String: ExploreKind] = [
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
    static let propertyKinds: [String: ExploreKind] = [
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
