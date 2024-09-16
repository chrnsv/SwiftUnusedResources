//
//  File.swift
//  
//
//  Created by Alexander Chernousov on 16.09.2024.
//

import Foundation

public struct Configuration: Codable {
    public let exclude: Exclude
    
    public struct Exclude: Codable {
        let sources: [String]
        let resources: [String]
    }
}
