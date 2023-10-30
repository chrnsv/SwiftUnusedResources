//
//  File.swift
//  
//
//  Created by Alexander Chernousov on 30.10.2023.
//

import Foundation

actor Storage {
    private(set) var exploredResources: [ExploreResource] = []
    private(set) var exploredUsages: [ExploreUsage] = []
    private(set) var unused: [ExploreResource] = []
    
    func addUsages(_ usages: some Sequence<ExploreUsage>) {
        exploredUsages.append(contentsOf: usages)
    }
    
    func addResource(_ resource: ExploreResource) {
        exploredResources.append(resource)
    }
    
    func addResources(_ resources: some Sequence<ExploreResource>) {
        exploredResources.append(contentsOf: resources)
    }
    
    func addUnused(_ resource: ExploreResource) {
        unused.append(resource)
    }
    
    func clean() {
        exploredResources.removeAll()
        exploredUsages.removeAll()
        unused.removeAll()
    }
}
