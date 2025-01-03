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
    
    struct Exclude: Codable, Sendable {
        let sources: [String]?
        let resources: [String]?
        let assets: [String]?
    }
    
    enum Kind: String, Codable, Sendable {
        case image
        case color
    }
}
