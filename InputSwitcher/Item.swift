//
//  Item.swift
//  InputSwitcher
//
//  Created by takeuchi-yuya on 2026/02/12.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
