//
//  Path+Utils.swift
//  
//
//  Created by Alexander Chernousov on 16.12.2023.
//

import Foundation
import PathKit

extension Path {
    var size: Int {
        if isDirectory {
            let childrenPaths = try? children()
            return (childrenPaths ?? []).reduce(0) { $0 + $1.size }
        }
        else {
            // Skip hidden files
            if lastComponent.hasPrefix(".") {
                return 0
            }
            
            let attr = try? FileManager.default.attributesOfItem(atPath: absolute().string)
            if let num = attr?[.size] as? NSNumber {
                return num.intValue
            }
            else {
                return 0
            }
        }
    }

    /// Recursively finds files and directories with the given extension, like the `**/*.ext` glob:
    /// the match is case-sensitive. Hidden entries are skipped, including everything inside
    /// hidden directories. Results are sorted.
    func descendants(withExtension ext: String) -> [Path] {
        descendants(withExtensions: [ext])[ext] ?? []
    }

    /// Same as `descendants(withExtension:)` for several extensions in a single walk of the
    /// tree. Every requested extension has an entry (possibly empty); each entry is sorted.
    func descendants(withExtensions extensions: Set<String>) -> [String: [Path]] {
        var subpaths: [String: [String]] = [:]

        for ext in extensions {
            subpaths[ext] = []
        }

        guard let enumerator = FileManager.default.enumerator(atPath: string) else {
            return subpaths.mapValues { _ in [] }
        }

        while let subpath = enumerator.nextObject() as? String {
            let name = NSString(string: subpath).lastPathComponent

            if name.hasPrefix(".") {
                // Called on a file, `skipDescendants()` skips the rest of its parent directory
                if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
                    enumerator.skipDescendants()
                }
            }
            else {
                let ext = NSString(string: name).pathExtension

                if extensions.contains(ext) {
                    subpaths[ext, default: []].append(subpath)
                }
            }
        }

        return subpaths.mapValues { paths in
            paths
                .sorted()
                .map { self + $0 }
        }
    }

    func containsDirectory(withExtension ext: String) -> Bool {
        // Normalize the target extension: remove leading dot(s) and lowercase
        let normalizedExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()

        let directoryComponents = NSString(string: string)
            .pathComponents
            .dropLast()

        return directoryComponents.contains { component in
            let componentExt = Path(component).extension?
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()

            return componentExt == normalizedExt
        }
    }
}
