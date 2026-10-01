//
//  NavigationWrapper.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 7.10.2025.
//

import SwiftUI

public struct Navigation {
    public let router: Router
    public let information: NavigationInformations
}

/// The nearest `Router` together with how the view was reached (pushed,
/// presented, root).
///
///     @NavigationWrapper private var navigation
///
/// Behaves like `RouterWrapper` when there is no router in the environment.
@propertyWrapper
public struct NavigationWrapper: DynamicProperty {
    @Environment(Router.self)
    private var routerInstance: Router?

    @Environment(NavigationInformations.self)
    private var navigationInformationsInstance: NavigationInformations?

    public init() {}

    @MainActor
    public var wrappedValue: Navigation {
        let router = MissingRouter.resolve(routerInstance, in: "NavigationWrapper")
        let information = navigationInformationsInstance ?? router.navigationInformation(isPushed: false)
        return Navigation(router: router, information: information)
    }
}
