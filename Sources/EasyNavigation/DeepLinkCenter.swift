//
//  DeepLinkCenter.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import Foundation

public actor DeepLinkCenter<ViewDestination: ViewDestinationRepresentable> {
    // Keeps links that arrived while app was "locked"
    private var pending: [ViewDestination] = []
    let routerStack: RouterStack
    
    public init(routerStack: RouterStack) {
        self.routerStack = routerStack
    }

    /// Call from AppDelegate / notification delegate / openURL
    public func enqueue(_ link: URL) async {
        guard let destination = ViewDestination(from: link) else { return }
        pending.append(destination)
        await tryDeliver()
    }

    /// Call whenever login, onboarding, etc. finishes
    func tryDeliver() async {
        // get front-most router (you expose this via Environment)
        let router = await MainActor.run { routerStack.topMostRouter }
        if let router = router,
           !pending.isEmpty
        {
            // Remove first before async operation to avoid potential duplicates
            let firstLink = pending.removeFirst()
            // Since ViewDestination now conforms to Sendable, it's safe to pass across actor boundaries
            await route(firstLink, on: router)
            
            // Continue processing pending links
            if !pending.isEmpty {
                await tryDeliver()
            }
        }
    }

    @MainActor
    private func route(_ destination: ViewDestination, on router: Router) async {
        let view = destination.view
        router.present {
            view
        }
    }
}
