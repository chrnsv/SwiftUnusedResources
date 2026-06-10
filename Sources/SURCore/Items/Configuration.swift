//
//  Configuration.swift
//
//
//  Created by Alexander Chernousov on 16.09.2024.
//

import Foundation

struct Configuration: Codable, Sendable {
    let exclude: Exclude?
    let kinds: [Kind]?
    let symbols: Symbols?

    struct Exclude: Codable, Sendable {
        let sources: [String]?
        let resources: [String]?
        let assets: [String]?
    }

    enum Kind: String, Codable, Sendable {
        case image
        case color
    }

    /// User-supplied additions to the built-in tables of color/image-carrying symbols,
    /// e.g. custom SwiftUI modifiers (`calls`) or custom UIKit-style properties (`properties`).
    struct Symbols: Codable, Sendable {
        let calls: KindNames?
        let properties: KindNames?

        struct KindNames: Codable, Sendable {
            let color: [String]?
            let image: [String]?
        }
    }
}
