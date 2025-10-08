//
//  NavigationInformations.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import SwiftUI

@Observable
open class NavigationInformations {
    public let isPushed: Bool
    public let isPresented: Bool
    public let navigationType: NavigationType
    let id: String
    
    init(
        isPushed: Bool,
        isPresenting: Bool,
        navigationType: NavigationType
    ) {
        self.isPushed = isPushed
        self.navigationType = navigationType
        self.isPresented = isPresenting
        id = UUID().uuidString
    }
    
    public enum NavigationType {
        case root
        case present
        case sheet
    }
}
