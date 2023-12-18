//
//  Int+Utils.swift
//  
//
//  Created by Alexander Chernousov on 16.12.2023.
//

import Foundation

extension Int {
    private static let fileSizeSuffix = ["B", "KB", "MB", "GB"]
    
    public var humanFileSize: String {
        var level = 0
        var num = Float(self)
        while num > 1000 && level < 3 {
            num /= 1000.0
            level += 1
        }
        
        if level == 0 {
            return "\(Int(num)) \(Self.fileSizeSuffix[level])"
        }
        else {
            return String(format: "%.2f \(Self.fileSizeSuffix[level])", num)
        }
    }
}
