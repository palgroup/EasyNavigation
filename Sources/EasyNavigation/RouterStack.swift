//
//  RouterStack.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import SwiftUI

@Observable
@MainActor
public final class RouterStack {
    public init() {}

    private struct WeakRouter {
        weak var router: Router?
    }

    @ObservationIgnored
    private var stack: [WeakRouter] = []

    deinit {
        stack.removeAll()
    }

    /// Call in `ViewNavigationWrapper.onAppear`
    func push(_ router: Router) {
        print("🔄 [RouterStack] PUSH - Router: \(router.id)")
        print("🔄 [RouterStack] PUSH - Stack BEFORE: \(stack.count) items")

        // Cleanup dead references first
        stack.removeAll { $0.router == nil }

        if !stack.contains(where: { $0.router?.id == router.id }) {
            stack.append(WeakRouter(router: router))
            print("✅ [RouterStack] PUSH - Added router")
        } else {
            print("⚠️ [RouterStack] PUSH - Router already in stack")
        }

        print("🔄 [RouterStack] PUSH - Stack AFTER: \(stack.count) items")
    }

    /// Call in `ViewNavigationWrapper.onDisappear`
    func pop(_ router: Router) {
        print("🔄 [RouterStack] POP - Router: \(router.id)")
        print("🔄 [RouterStack] POP - Stack BEFORE: \(stack.count) items")

        let countBefore = stack.count
        stack.removeAll { $0.router?.id == router.id || $0.router == nil }

        print("🔄 [RouterStack] POP - Removed \(countBefore - stack.count) items")
        print("🔄 [RouterStack] POP - Stack AFTER: \(stack.count) items")
    }

    /// Router currently on screen (sheet / fullscreen içinde dâhil)
    var topMostRouter: Router? {
        // Clean up nil references and return last valid router
        stack.removeAll { $0.router == nil }
        return stack.last?.router
    }

    /// Cleanup all routers in stack before removing them
    /// This breaks retain cycles and ensures proper deallocation
    func cleanupAllRouters() {
        print("🧹 [RouterStack] CLEANUP ALL - Stack BEFORE: \(stack.count) items")

        // Cleanup each router to break retain cycles
        for weakRouter in stack {
            if let router = weakRouter.router {
                router.cleanup()
            }
        }

        print("✅ [RouterStack] CLEANUP ALL - All routers cleaned up")
    }

    func removeAllPendings() {
        print("🗑️ [RouterStack] REMOVE ALL - Stack BEFORE: \(stack.count) items")
        stack.removeAll()
        print("🗑️ [RouterStack] REMOVE ALL - Stack AFTER: \(stack.count) items")
    }
}
