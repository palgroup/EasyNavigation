//
//  DestinationWrapper.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import Foundation
import SwiftUI

public struct DestinationWrapper: Identifiable, Hashable, @unchecked Sendable {
    public let id = UUID()
    let destination: AnyView
    let allowsBackSwipe: Bool

    init(destination: AnyView, allowsBackSwipe: Bool = true) {
        self.destination = destination
        self.allowsBackSwipe = allowsBackSwipe
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
