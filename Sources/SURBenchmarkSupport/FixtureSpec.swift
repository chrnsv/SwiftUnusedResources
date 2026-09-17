package struct FixtureSpec: Equatable, Sendable {
    package static let small = FixtureSpec(swiftFiles: 100, imageSets: 150, colorSets: 40, looseImages: 10, xibs: 5)
    package static let medium = FixtureSpec(swiftFiles: 1_000, imageSets: 1_500, colorSets: 400, looseImages: 100, xibs: 50)
    package static let large = FixtureSpec(swiftFiles: 5_000, imageSets: 7_500, colorSets: 2_000, looseImages: 500, xibs: 200)

    package var swiftFiles: Int
    package var imageSets: Int
    package var colorSets: Int
    package var looseImages: Int
    package var xibs: Int
    package var unusedShare: Double
    package var seed: UInt64

    package init(
        swiftFiles: Int,
        imageSets: Int,
        colorSets: Int,
        looseImages: Int,
        xibs: Int,
        unusedShare: Double = 0.15,
        seed: UInt64 = 0x5EED
    ) {
        self.swiftFiles = swiftFiles
        self.imageSets = imageSets
        self.colorSets = colorSets
        self.looseImages = looseImages
        self.xibs = xibs
        self.unusedShare = unusedShare
        self.seed = seed
    }

    package init?(sizeName: String) {
        switch sizeName {
        case "small": self = .small
        case "medium": self = .medium
        case "large": self = .large
        default: return nil
        }
    }
}
