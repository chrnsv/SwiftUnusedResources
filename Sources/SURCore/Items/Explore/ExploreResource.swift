//
//  File.swift
//
//
//  Created by Alexander Chernousov on 30.10.2023.
//

import Foundation

package struct ExploreResource: Sendable {
    let name: String
    let type: ResourceType
    let kind: ExploreKind
    let path: String
    var usedCount: Int = 0

    package enum ResourceType: Sendable {
        case asset(assets: String)
        case file
    }
}
