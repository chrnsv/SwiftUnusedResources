import Foundation
import PathKit
import Testing

@testable import SURCore

@Suite("Utility helpers (humanFileSize, count(of:), Path utils)")
struct UtilsTests {
    // MARK: - Int.humanFileSize

    @Test("Formats zero bytes")
    func zeroBytes() {
        #expect(0.humanFileSize == "0 B")
    }

    @Test("Formats bytes below the threshold")
    func plainBytes() {
        #expect(999.humanFileSize == "999 B")
    }

    @Test("Keeps exactly 1000 in bytes (threshold is exclusive)")
    func thousandBytes() {
        #expect(1000.humanFileSize == "1000 B")
    }

    @Test("Formats kilobytes with two decimals")
    func kilobytes() {
        #expect(1500.humanFileSize == "1.50 KB")
    }

    @Test("Formats megabytes")
    func megabytes() {
        #expect(1_500_000.humanFileSize == "1.50 MB")
    }

    @Test("Formats gigabytes")
    func gigabytes() {
        #expect(2_500_000_000.humanFileSize == "2.50 GB")
    }

    @Test("Caps the unit at gigabytes")
    func capsAtGigabytes() {
        #expect(5_000_000_000_000.humanFileSize == "5000.00 GB")
    }

    // MARK: - String.count(of:)

    @Test("Counts zero occurrences in an empty string")
    func countInEmptyString() {
        #expect("".count(of: ",") == 0)
    }

    @Test("Counts zero occurrences when the character is absent")
    func countAbsentCharacter() {
        #expect("abc".count(of: ",") == 0)
    }

    @Test("Counts separators in a list")
    func countSeparators() {
        #expect("a,b,c".count(of: ",") == 2)
    }

    @Test("Counts when every character matches")
    func countAllMatching() {
        #expect("....".count(of: ".") == 4)
    }

    @Test("Counts multi-scalar characters")
    func countEmoji() {
        #expect("🌟a🌟".count(of: "🌟") == 2)
    }

    // MARK: - Path.containsDirectory(withExtension:)

    @Test("Detects a directory with the extension in the middle of the path")
    func containsDirectoryMidPath() {
        #expect(Path("a/b.icon/c.png").containsDirectory(withExtension: "icon"))
    }

    @Test("Normalizes a leading dot in the extension argument")
    func containsDirectoryLeadingDot() {
        #expect(Path("a/b.icon/c.png").containsDirectory(withExtension: ".icon"))
    }

    @Test("Matches extensions case-insensitively")
    func containsDirectoryCaseInsensitive() {
        #expect(Path("a/B.ICON/c.png").containsDirectory(withExtension: "icon"))
        #expect(Path("a/b.icon/c.png").containsDirectory(withExtension: "ICON"))
    }

    @Test("Ignores the last path component")
    func containsDirectoryIgnoresLastComponent() {
        #expect(!Path("a/b.icon").containsDirectory(withExtension: "icon"))
    }

    @Test("Returns false when no component has the extension")
    func containsDirectoryNoMatch() {
        #expect(!Path("a/b/c.png").containsDirectory(withExtension: "icon"))
    }

    // MARK: - Path.size

    @Test("Returns the byte count of a single file")
    func sizeOfFile() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let file = try tmp.write("file.txt", "hello")
        #expect(file.size == 5)
    }

    @Test("Sums children recursively for a directory")
    func sizeOfDirectory() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("a.txt", "12345")
        try tmp.write("nested/b.txt", "1234567890")

        #expect(tmp.path.size == 15)
    }

    @Test("Skips hidden files")
    func sizeSkipsHiddenFiles() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("visible.txt", "12345")
        try tmp.write(".hidden", "secret")

        #expect(tmp.path.size == 5)
    }

    @Test("Returns zero for a nonexistent path")
    func sizeOfNonexistentPath() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        #expect((tmp.path + "missing.txt").size == 0)
    }

    @Test("Returns zero for an empty directory")
    func sizeOfEmptyDirectory() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        #expect(tmp.path.size == 0)
    }
}
