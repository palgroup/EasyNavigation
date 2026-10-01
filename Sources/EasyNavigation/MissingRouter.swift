//
//  MissingRouter.swift
//  EasyNavigation
//
//  What `RouterWrapper` and `NavigationWrapper` do when a view reads them
//  without a `Router` in its environment — i.e. outside every navigation
//  wrapper.
//
//  - In an Xcode preview a screen is often rendered on its own. It gets a
//    detached router, so the preview draws instead of crashing; navigating
//    from it does nothing.
//  - In the app the same thing is a wiring bug: a button that navigates would
//    silently do nothing. It stops with a message that names the fix, instead
//    of SwiftUI's generic "No Observable object of type Router found".
//

import SwiftUI

@MainActor
enum MissingRouter {
    /// Not attached to any navigation stack; its operations have nowhere to go.
    static let detached = Router { EmptyView() }

    static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// The router to hand out instead, or `nil` when the caller must stop.
    static func substitute(isRunningForPreviews: Bool = isRunningForPreviews) -> Router? {
        isRunningForPreviews ? detached : nil
    }

    static func resolve(_ router: Router?, in wrapper: String) -> Router {
        if let router { return router }
        guard let substitute = substitute() else {
            preconditionFailure(
                """
                EasyNavigation: \(wrapper) found no Router in the environment. \
                The view is outside every navigation wrapper, so navigating from it would do nothing. \
                Put it under ViewNavigationWrapper (or TypedNavigationWrapper / SplitNavigationWrapper).
                """
            )
        }
        NavigationLogger.debug("\(wrapper) - no Router in a preview; using a detached one")
        return substitute
    }
}
