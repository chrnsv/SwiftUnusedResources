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

    // MARK: - Path.descendants(withExtension:)

    @Test("Finds files at the root and in nested directories, sorted")
    func descendantsFindsNestedFiles() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("b.swift", "")
        try tmp.write("nested/deep/a.swift", "")
        try tmp.write("nested/c.txt", "")

        #expect(tmp.path.descendants(withExtension: "swift") == [
            tmp.path + "b.swift",
            tmp.path + "nested/deep/a.swift",
        ])
    }

    @Test("Matches directories and keeps descending into them")
    func descendantsMatchesDirectories() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("Assets.xcassets/Icon.imageset/Contents.json", "{}")
        try tmp.write("Assets.xcassets/Group/Nested.imageset/Contents.json", "{}")

        #expect(tmp.path.descendants(withExtension: "xcassets") == [tmp.path + "Assets.xcassets"])
        #expect(tmp.path.descendants(withExtension: "imageset") == [
            tmp.path + "Assets.xcassets/Group/Nested.imageset",
            tmp.path + "Assets.xcassets/Icon.imageset",
        ])
    }

    @Test("One walk buckets several extensions, each bucket sorted, absent extensions empty")
    func descendantsWithExtensions() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("b.swift", "")
        try tmp.write("nested/a.swift", "")
        try tmp.write("nested/logo.png", "")
        try tmp.write("Assets.xcassets/Icon.imageset/icon.png", "")

        let buckets = tmp.path.descendants(withExtensions: ["swift", "png", "xcassets", "pdf"])

        #expect(buckets["swift"] == [tmp.path + "b.swift", tmp.path + "nested/a.swift"])
        #expect(buckets["png"] == [tmp.path + "Assets.xcassets/Icon.imageset/icon.png", tmp.path + "nested/logo.png"])
        #expect(buckets["xcassets"] == [tmp.path + "Assets.xcassets"])
        #expect(buckets["pdf"]?.isEmpty == true)
        #expect(buckets["imageset"] == nil)
    }

    @Test("A pruned extension lists the matched directory but not its contents")
    func descendantsPruning() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("Assets.xcassets/Icon.imageset/icon.png", "")
        try tmp.write("Assets.xcassets/Nested.xcassets/Contents.json", "{}")
        try tmp.write("Images/logo.png", "")

        let buckets = tmp.path.descendants(withExtensions: ["xcassets", "png"], pruning: ["xcassets"])

        #expect(buckets["xcassets"] == [tmp.path + "Assets.xcassets"])
        #expect(buckets["png"] == [tmp.path + "Images/logo.png"])
    }

    @Test("A pruned extension on a file does not hide its siblings")
    func descendantsPruningFile() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("dir/a.xcassets", "not a directory")
        try tmp.write("dir/b.png", "")
        try tmp.write("dir/nested/c.png", "")

        let buckets = tmp.path.descendants(withExtensions: ["xcassets", "png"], pruning: ["xcassets"])

        #expect(buckets["xcassets"] == [tmp.path + "dir/a.xcassets"])
        #expect(buckets["png"] == [tmp.path + "dir/b.png", tmp.path + "dir/nested/c.png"])
    }

    @Test("Does not match the receiver itself")
    func descendantsExcludesReceiver() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let assets = tmp.path + "Assets.xcassets"
        try assets.mkpath()

        #expect(assets.descendants(withExtension: "xcassets").isEmpty)
    }

    @Test("Skips hidden files and does not descend into hidden directories")
    func descendantsHiddenEntries() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write(".hidden.swift", "")
        try tmp.write(".cache/a.swift", "")
        try tmp.write(".build/checkouts/Dependency/b.swift", "")
        try tmp.write("visible/.nested/c.swift", "")
        try tmp.write("visible/d.swift", "")

        #expect(tmp.path.descendants(withExtension: "swift") == [tmp.path + "visible/d.swift"])
    }

    @Test("A hidden file does not hide its siblings")
    func descendantsHiddenFileKeepsSiblings() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("dir/.DS_Store", "")
        try tmp.write("dir/a.swift", "")
        try tmp.write("dir/nested/b.swift", "")
        try tmp.write("dir/z.swift", "")

        #expect(tmp.path.descendants(withExtension: "swift") == [
            tmp.path + "dir/a.swift",
            tmp.path + "dir/nested/b.swift",
            tmp.path + "dir/z.swift",
        ])
    }

    @Test("Matches the extension case-sensitively")
    func descendantsCaseSensitive() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("a.PNG", "")
        try tmp.write("b.png", "")

        #expect(tmp.path.descendants(withExtension: "png") == [tmp.path + "b.png"])
    }

    @Test("Returns nothing for a nonexistent path")
    func descendantsOfNonexistentPath() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        #expect((tmp.path + "missing").descendants(withExtension: "swift").isEmpty)
    }
}
