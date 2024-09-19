//
//  File.swift
//
//
//  Created by Alexander Chernousov on 30.10.2023.
//

import Foundation

enum ExploreUsage {
    case string(_ value: String, _ kind: ExploreKind)
    case regexp(_ pattern: String, _ kind: ExploreKind)
    case rswift(_ identifier: String, _ kind: ExploreKind)
}
