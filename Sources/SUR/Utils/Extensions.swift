import Foundation
import PathKit

extension String: Error { }

extension String {
    func count(of needle: Character) -> Int {
        return reduce(0) {
            $1 == needle ? $0 + 1 : $0
        }
    }
}

extension Path {
    var size: Int {
        if isDirectory {
            let childrenPaths = try? children()
            return (childrenPaths ?? []).reduce(0) { $0 + $1.size }
        }
        else {
            // Skip hidden files
            if lastComponent.hasPrefix(".") { return 0 }
            let attr = try? FileManager.default.attributesOfItem(atPath: absolute().string)
            if let num = attr?[.size] as? NSNumber {
                return num.intValue
            }
            else {
                return 0
            }
        }
    }
}

extension Int {
    private static let fileSizeSuffix = ["B", "KB", "MB", "GB"]
    
    public var humanFileSize: String {
        var level = 0
        var num = Float(self)
        while num > 1000 && level < 3 {
            num /= 1000.0
            level += 1
        }
        
        if level == 0 {
            return "\(Int(num)) \(Self.fileSizeSuffix[level])"
        }
        else {
            return String(format: "%.2f \(Self.fileSizeSuffix[level])", num)
        }
    }
}
