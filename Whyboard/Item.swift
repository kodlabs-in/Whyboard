//
//  Item.swift
//  Whyboard
//
//  Created by Prince on 15/09/26.
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
