//
//  MissingRouter.swift
//  EasyNavigation
//
//  What `@Router` and `@NavigationWrapper` do when a view reads them with no
//  router in its environment — i.e. outside every navigation wrapper.
//
//  - In an Xcode preview a screen is often rendered on its own. It gets a
//    detached router, so the preview draws instead of crashing; navigating
//    from it does nothing.
//  - In the app the same thing is a wiring bug: a button that navigates would
//    silently do nothing. It stops with a message that names the fix, instead
//    of SwiftUI's generic "No Observable object of type … found".
//

import SwiftUI

@MainActor
enum MissingRouter {
    /// Not attached to any navigation stack; its operations have nowhere to go.
    static let detached = _Router { EmptyView() }

    static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// The router to hand out instead, or `nil` when the caller must stop.
    static func substitute(isRunningForPreviews: Bool = isRunningForPreviews) -> _Router? {
        isRunningForPreviews ? detached : nil
    }

    static func resolve(
        _ router: _Router?,
        in wrapper: String,
        isRunningForPreviews: Bool = isRunningForPreviews
    ) -> _Router {
        if let router { return router }
        guard let substitute = substitute(isRunningForPreviews: isRunningForPreviews) else {
            // `fatalError`, not `preconditionFailure`: the message is the
            // point, and a precondition drops it in optimized builds.
            fatalError(
                """
                EasyNavigation: \(wrapper) found no router in the environment. \
                The view is outside every ViewNavigationWrapper, so navigating from it would do nothing. \
                Put it under a ViewNavigationWrapper, or pass it the router as a value.
                """
            )
        }
        NavigationLogger.debug("\(wrapper) - no router in a preview; using a detached one")
        return substitute
    }
}
