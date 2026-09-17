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
    /// the match is case-sensitive and skips hidden entries. Results are sorted.
    func descendants(withExtension ext: String) -> [Path] {
        guard let enumerator = FileManager.default.enumerator(atPath: string) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? String }
            .filter { subpath in
                let name = NSString(string: subpath).lastPathComponent
                return !name.hasPrefix(".") && NSString(string: name).pathExtension == ext
            }
            .sorted()
            .map { self + $0 }
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
