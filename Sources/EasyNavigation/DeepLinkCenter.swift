//
//  DeepLinkCenter.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import Foundation
import SwiftUI

public actor DeepLinkCenter: ObservableObject {
    // Keeps links that arrived while app was "locked"
    private var pending: [any ViewDestinationRepresentable] = []
    weak var routerStack: RouterStack?
    
    deinit {
        pending.removeAll()
        routerStack = nil
    }
    
    public init(routerStack: RouterStack) {
        self.routerStack = routerStack
    }

    /// Call from AppDelegate / notification delegate / openURL
    public func enqueue(_ destination: ViewDestinationRepresentable) async {
        pending.append(destination)
        await tryDeliver()
    }

    /// Call whenever login, onboarding, etc. finishes
    @MainActor
    func tryDeliver() async {
        // get front-most router (you expose this via Environment)
        let router = await routerStack?.topMostRouter
        if let router = router,
           await !pending.isEmpty
        {
            // Remove first before async operation to avoid potential duplicates
            let firstLink = await removeFirst()
            // Since ViewDestination now conforms to Sendable, it's safe to pass across actor boundaries
            await route(firstLink, on: router)
            
            // Continue processing pending links
            if await !pending.isEmpty {
                await tryDeliver()
            }
        }
    }

    @MainActor
    private func route(_ destination: any ViewDestinationRepresentable, on router: Router) async {
        let view = destination.view
        router.present {
            view
        }
    }
    
    private func removeFirst() -> ViewDestinationRepresentable {
        pending.removeFirst()
    }
}
