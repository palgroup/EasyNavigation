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

/// The nearest router together with how the view was reached (pushed,
/// presented, root).
///
///     @NavigationWrapper private var navigation
///
/// Behaves like `@Router` when there is no router in the environment.
@propertyWrapper
public struct NavigationWrapper: DynamicProperty {
    @Environment(_Router.self)
    private var routerInstance: _Router?

    @Environment(NavigationInformations.self)
    private var navigationInformationsInstance: NavigationInformations?

    public init() {}

    @MainActor
    public var wrappedValue: Navigation {
        let router = MissingRouter.resolve(routerInstance, in: "@NavigationWrapper")
        let information = navigationInformationsInstance ?? router.navigationInformation(isPushed: false)
        return Navigation(router: Router(router), information: information)
    }
}
