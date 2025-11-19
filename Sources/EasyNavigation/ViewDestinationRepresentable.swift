//
//  ViewDestinationRepresentable.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import Foundation
import SwiftUI

public protocol ViewDestinationRepresentable: Sendable {
    var view: AnyView { get }
}
