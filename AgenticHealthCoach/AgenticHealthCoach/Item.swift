//
//  Item.swift
//  AgenticHealthCoach
//
//  Created by Aimdrone 254 on 4/24/26.
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
