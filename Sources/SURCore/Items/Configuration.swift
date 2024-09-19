//
//  Configuration.swift
//
//
//  Created by Alexander Chernousov on 16.09.2024.
//

import Foundation

struct Configuration: Codable {
    let exclude: Exclude?
    let kinds: [Kind]?
    
    struct Exclude: Codable {
        let sources: [String]?
        let resources: [String]?
        let assets: [String]?
    }
    
    enum Kind: String, Codable {
        case image
        case color
    }
}
