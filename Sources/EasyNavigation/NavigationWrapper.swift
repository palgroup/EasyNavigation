//
//  RouterDecorator.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 7.10.2025.
//

import SwiftUI
import Combine

public struct Navigation {
    public let router: Router
    public let information: NavigationInformations
}

@propertyWrapper
public struct NavigationWrapper: DynamicProperty {
    @Environment(Router.self)
    private var routerInstance
    
    @Environment(NavigationInformations.self)
    private var navigationInformationsInstance
    
    public init() {}
    
    /// View içinde `@RouterDecorator private var router` dediğinde bu değer gelecek
    public var wrappedValue: Navigation {
        Navigation(router: routerInstance, information: navigationInformationsInstance)
    }
}
