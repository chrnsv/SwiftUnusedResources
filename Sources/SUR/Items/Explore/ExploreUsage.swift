//
//  File.swift
//
//
//  Created by Alexander Chernousov on 30.10.2023.
//

import Foundation

enum ExploreUsage {
    case string(_ value: String)
    case regexp(_ pattern: String)
    case rswift(_ identifier: String)
}
