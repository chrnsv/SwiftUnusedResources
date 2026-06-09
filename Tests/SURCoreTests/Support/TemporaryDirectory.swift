import Foundation
import PathKit

/// A unique temporary directory for test fixtures, cleaned up via `remove()`.
struct TemporaryDirectory {
    let path: Path

    init() throws {
        path = Path(FileManager.default.temporaryDirectory.path) + "SURTests-\(UUID().uuidString)"

        try path.mkpath()
    }

    /// Writes `contents` to `relative` path inside the directory, creating intermediate directories.
    @discardableResult
    func write(_ relative: String, _ contents: String) throws -> Path {
        let filePath = path + relative

        try filePath.parent().mkpath()
        try filePath.write(contents)

        return filePath
    }

    func remove() {
        try? path.delete()
    }
}
