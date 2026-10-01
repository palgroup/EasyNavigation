//
//  RouterWrapper.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 8.10.2025.
//

import SwiftUI

/// The nearest `Router`, read from the environment.
///
///     @RouterWrapper private var router
///
/// Outside every navigation wrapper it does not crash in an Xcode preview (it
/// hands out a detached router) and stops with a clear message in the app.
/// See `MissingRouter`.
@propertyWrapper
public struct RouterWrapper: DynamicProperty {
    @Environment(Router.self)
    private var routerInstance: Router?

    public init() {}

    @MainActor
    public var wrappedValue: Router {
        MissingRouter.resolve(routerInstance, in: "RouterWrapper")
    }
}
