import Foundation
import Testing

@testable import SURCore

@Suite("R.swift to generated asset symbols rewriting")
struct RToGeneratedAssetsRewriterTests {
    private func rewritten(_ source: String) throws -> String {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let path = try tmp.write("Main.swift", source)
        try RToGeneratedAssetsRewriter().rewrite(fileAt: path.url, dryRun: false)

        return try path.read()
    }

    @Test("Rewrites a camelCase R.swift identifier to the same generated symbol")
    func camelCaseIdentifier() throws {
        let result = try rewritten("""
        import UIKit

        let image = R.image.star()!
        """)
        #expect(result == """
        import UIKit

        let image = UIImage(resource: .star)
        """)
    }

    @Test("Rewrites a snake_case R.swift identifier to the camel-cased Xcode symbol")
    func snakeCaseIdentifier() throws {
        let result = try rewritten("""
        import UIKit

        let image = R.image.bear_shy()!
        let color = R.color.brand_primary()
        let resource = R.image.mascot_bear_review_avatar
        """)
        #expect(result == """
        import UIKit

        let image = UIImage(resource: .bearShy)
        let color = UIColor(resource: .brandPrimary)
        let resource = ImageResource.mascotBearReviewAvatar
        """)
    }
}
