//
//  File.swift
//  
//
//  Created by Alexander Chernousov on 30.10.2023.
//

import Foundation
import PathKit

struct ExploreResource {
    let name: String
    let type: ResourceType
    let path: Path
    var usedCount: Int = 0
    
    enum ResourceType {
        case asset(assets: String)
        case image
    }

}
