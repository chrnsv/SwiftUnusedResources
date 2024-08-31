//
//  File.swift
//
//
//  Created by Alexander Chernousov on 30.10.2023.
//

import Foundation

enum ExploreUsage {
    case string(_ value: String, _ kind: Kind)
    case regexp(_ pattern: String, _ kind: Kind)
    case rswift(_ identifier: String, _ kind: Kind)
    
    enum Kind {
        case image
        case color
    }
}
