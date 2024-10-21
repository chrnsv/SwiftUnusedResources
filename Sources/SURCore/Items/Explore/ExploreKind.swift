//
//  File.swift
//  
//
//  Created by Alexander Chernousov on 31.08.2024.
//

import Foundation

enum ExploreKind: String, CaseIterable, Sendable {
    case image
    case color
}

extension ExploreKind {
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
