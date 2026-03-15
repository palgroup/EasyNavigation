//
//  RouterWrapper.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 8.10.2025.
//

import SwiftUI

@propertyWrapper
public struct RouterWrapper: DynamicProperty {
    @Environment(Router.self)
    private var routerInstance
    
    public init() {}
    
    /// View içinde `@RouterDecorator private var router` dediğinde bu değer gelecek
    public var wrappedValue: Router {
        routerInstance
    }
}
