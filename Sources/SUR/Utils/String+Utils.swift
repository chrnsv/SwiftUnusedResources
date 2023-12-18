//
//  String+Utils.swift
//  
//
//  Created by Alexander Chernousov on 16.12.2023.
//

import Foundation

extension String: Error { }

extension String {
    func count(of needle: Character) -> Int {
        return reduce(0) {
            $1 == needle ? $0 + 1 : $0
        }
    }
}
