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
        "tint": .color,
        "accentColor": .color,
        "background": .color,
        "fill": .color,
        "stroke": .color,
        "strokeBorder": .color,
        "border": .color,
        "shadow": .color,
        "listRowBackground": .color,
        "toolbarBackground": .color,
        "presentationBackground": .color,
        "underline": .color,
        "strikethrough": .color,
        "setTitleColor": .color,
        "setTitleShadowColor": .color,
        "setImage": .image,
        "setBackgroundImage": .image,
    ]

    /// Well-known UIKit color/image properties whose assignment carries generated asset
    /// symbols, e.g. `label.textColor = .brand` or `imageView.image = .star`.
    static let propertyKinds: [String: ExploreKind] = [
        "textColor": .color,
        "backgroundColor": .color,
        "tintColor": .color,
        "barTintColor": .color,
        "highlightedTextColor": .color,
        "shadowColor": .color,
        "separatorColor": .color,
        "onTintColor": .color,
        "thumbTintColor": .color,
        "progressTintColor": .color,
        "trackTintColor": .color,
        "pageIndicatorTintColor": .color,
        "currentPageIndicatorTintColor": .color,
        "image": .image,
        "highlightedImage": .image,
        "selectedImage": .image,
        "shadowImage": .image,
        "backgroundImage": .image,
        "onImage": .image,
        "offImage": .image,
        "minimumValueImage": .image,
        "maximumValueImage": .image,
    ]
}
