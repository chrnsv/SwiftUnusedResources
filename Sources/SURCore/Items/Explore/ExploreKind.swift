//
//  File.swift
//  
//
//  Created by Alexander Chernousov on 31.08.2024.
//

import Foundation

enum ExploreKind: Equatable, Hashable {
    case asset(Asset)
    case string
    
    var rawValue: String {
        switch self {
        case .asset(.image): "image"
        case .asset(.color): "color"
        case .string: "string"
        }
    }
}

extension ExploreKind: CaseIterable {
    static let allCases: [ExploreKind] = [
        .asset(.image),
        .asset(.color),
        .string
    ]
    
    enum Asset: String, CaseIterable {
        case image
        case color
    }
}

extension ExploreKind.Asset {
    var uiClassName: String {
        switch self {
        case .image: "UIImage"
        case .color: "UIColor"
        }
    }
    
    var swiftUIClassName: String {
        switch self {
        case .image: "Image"
        case .color: "Color"
        }
    }
}
