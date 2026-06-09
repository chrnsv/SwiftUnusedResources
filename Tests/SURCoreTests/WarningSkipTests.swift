import Foundation
import Testing

@testable import SURCore

@Suite("// sur:skip suppresses the unguessable-pattern warning", .serialized)
struct WarningSkipTests {
    /// Parses `source` with warnings enabled and returns everything printed to stdout.
    private func warnings(for source: String) -> String {
        let pipe = Pipe()
        let original = dup(fileno(stdout))
        fflush(stdout)
        dup2(pipe.fileHandleForWriting.fileDescriptor, fileno(stdout))

        let parser = SwiftParser(showWarnings: true, kinds: [.image, .color])
        _ = parser.parse(source: source)

        fflush(stdout)
        dup2(original, fileno(stdout))
        close(original)
        pipe.fileHandleForWriting.closeFile()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Baseline: warning is emitted without the directive

    @Test("Warns for an unguessable SwiftUI Image")
    func warnsForSwiftUIImage() {
        let output = warnings(for: """
        import SwiftUI

        let view = Image(dynamicName)
        """)

        #expect(output.contains("Couldn't guess match, please specify pattern"))
    }

    @Test("Warns for an unguessable UIImage(named:)")
    func warnsForUIImage() {
        let output = warnings(for: """
        import UIKit

        let image = UIImage(named: dynamicName)
        """)

        #expect(output.contains("Couldn't guess match, please specify pattern"))
    }

    // MARK: - Suppression with // sur: skip

    @Test("Skips the warning for a SwiftUI Image annotated with // sur: skip")
    func skipsSwiftUIImage() {
        let output = warnings(for: """
        import SwiftUI

        // sur: skip
        let view = Image(dynamicName)
        """)

        #expect(!output.contains("Couldn't guess match"))
    }

    @Test("Skips the warning for a UIImage(named:) annotated with // sur: skip")
    func skipsUIImage() {
        let output = warnings(for: """
        import UIKit

        // sur: skip
        let image = UIImage(named: dynamicName)
        """)

        #expect(!output.contains("Couldn't guess match"))
    }

    @Test("Honors the directive in a trailing line comment")
    func skipsTrailingComment() {
        let output = warnings(for: """
        import SwiftUI

        let view = Image(dynamicName) // sur: skip
        """)

        #expect(!output.contains("Couldn't guess match"))
    }

    @Test("Honors the directive without a space after the colon")
    func skipsWithoutSpace() {
        let output = warnings(for: """
        import SwiftUI

        // sur:skip
        let view = Image(dynamicName)
        """)

        #expect(!output.contains("Couldn't guess match"))
    }

    @Test("Ignores an unrelated comment")
    func ignoresUnrelatedComment() {
        let output = warnings(for: """
        import SwiftUI

        // just a regular comment
        let view = Image(dynamicName)
        """)

        #expect(output.contains("Couldn't guess match, please specify pattern"))
    }
}
