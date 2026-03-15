//
//  Router.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import SwiftUI
import Combine

@MainActor
@Observable
public class Router: Identifiable, Sendable {
    public let id = UUID().uuidString
    var root: AnyView
    var path: [DestinationWrapper] = []
    var fullScreenDestination: Router?
    @ObservationIgnored
    var onFullScreenDismiss: (() -> Void)?
    var sheetDestination: Router?
    @ObservationIgnored
    var onSheetDismiss: (() -> Void)?

    var rootViewID: UUID = UUID()

    @ObservationIgnored
    weak var parent: Router?

    // Operation queue for sequential execution (FIFO guaranteed)
    @ObservationIgnored
    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1  // Serial execution
        queue.qualityOfService = .userInteractive
        return queue
    }()

    // Navigation timing control
    @ObservationIgnored
    public var operationDelay: TimeInterval = 0.01  // 10ms default
    @ObservationIgnored
    public var waitForUIUpdate: Bool = true

    public var isPresenting: Bool {
        fullScreenDestination != nil || sheetDestination != nil
    }

    /// Whether the current top-of-stack view allows back swipe.
    /// Returns true when path is empty (root views always allow).
    public var isBackSwipeAllowed: Bool {
        path.last?.allowsBackSwipe ?? true
    }

    public init<Content: View>(
        parent: Router? = nil,
        @ViewBuilder root: @escaping () -> Content
    ) {
        self.parent = parent
        self.root = AnyView(root())
        self.rootViewID = UUID()
    }

    /// Cleanup all router references and destinations
    /// Call this before replacing root views to break retain cycles
    public func cleanup() {
        NavigationLogger.debug("CLEANUP - Starting cleanup")

        // Cancel all pending operations
        operationQueue.cancelAllOperations()

        // Recursively cleanup child routers first
        if let child = fullScreenDestination {
            child.cleanup()
        }
        if let child = sheetDestination {
            child.cleanup()
        }

        // Clear all navigation state
        path.removeAll()
        fullScreenDestination = nil
        sheetDestination = nil

        // Clear all callbacks to break potential retain cycles
        onFullScreenDismiss = nil
        onSheetDismiss = nil

        // CRITICAL: Clear root view to break environment capture
        // The AnyView captures the entire environment including this router
        // Replacing it with EmptyView breaks the retain cycle
        self.root = AnyView(EmptyView())

        NavigationLogger.debug("CLEANUP - Complete")
    }

    deinit {
        operationQueue.cancelAllOperations()
        NavigationLogger.debug("Router deiniting")
    }

    private func executeOperation(_ operation: @escaping @MainActor () -> Void) {
        let delay = waitForUIUpdate ? operationDelay : 0

        operationQueue.addOperation { [weak self] in
            // Execute on main thread since Router is @MainActor
            DispatchQueue.main.async {
                guard self != nil else { return }
                operation()
            }

            // Wait for UI update if needed
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
    }

    // MARK: - Navigation API
    public func push<Content: View>(allowBackSwipe: Bool = true, @ViewBuilder _ destination: @escaping () -> Content) {
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("PUSH - Router is nil, operation cancelled")
                return
            }
            NavigationLogger.debug("PUSH - Current path count: \(path.count)")

            let wrapper = DestinationWrapper(
                destination: AnyView(destination()),
                allowsBackSwipe: allowBackSwipe
            )
            path.append(wrapper)
            NavigationLogger.debug("PUSH - Pushed. New path count: \(path.count)")
        }
    }

    @MainActor
    private func replaceRootWithAnimation<Content: View>(_ newRootViewGenerator: @escaping () -> Content) {
        let newRootID = UUID()
        withAnimation(.default) {
            self.root = AnyView(newRootViewGenerator())
            self.rootViewID = newRootID
            self.path.removeAll()
        }
    }

    @MainActor
    private func replacingPushAnimated<Content: View>(_ destination: @escaping () -> Content) async {
        // Path is not empty. Replace the top view on the stack with an animation.
        let newDestinationWrapper = DestinationWrapper(destination: AnyView(destination()))

        // Operation 1: Append the new destination. This will be animated as a push.
        executeOperation { [weak self] in
            guard let self = self else { return }
            self.path.append(newDestinationWrapper)
        }

        do {
            try await Task.sleep(nanoseconds: 400_000_000) // 400ms
        } catch {
            NavigationLogger.warning("replacingPushAnimated - Task.sleep cancelled: \(error)")
            return
        }
        // Operation 2: Remove the item that was previously at the top (now second to last).
        // Do this without animation.
        executeOperation { [weak self] in
            guard let self = self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if self.path.count >= 2 {
                    self.path.remove(at: self.path.count - 2)
                }
            }
        }
    }

    public func replacingPush<Content: View>(@ViewBuilder _ destination: @escaping () -> Content) {
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("replacingPush - Router is nil")
                return
            }

            if self.path.isEmpty {
                // No pushed views — replace the root
                self.replaceRootWithAnimation(destination)
                NavigationLogger.debug("replacingPush - replaced root (path was empty)")
            } else {
                // Push new view, then remove the old top
                // Before append: path = [A, B, C] (C is current top)
                // After append:  path = [A, B, C, D]
                // Remove at count-2: removes C → path = [A, B, D] ✓
                self.path.append(DestinationWrapper(destination: AnyView(destination())))
                let removeIndex = self.path.count - 2
                guard removeIndex >= 0 else {
                    NavigationLogger.warning("replacingPush - unexpected state, removeIndex=\(removeIndex)")
                    return
                }
                self.path.remove(at: removeIndex)
                NavigationLogger.debug("replacingPush - replaced top, path count=\(self.path.count)")
            }
        }
    }

    public func removeAllPush<Content: View>(@ViewBuilder _ destination: @escaping () -> Content) {
        executeOperation { [weak self] in
            self?.replaceRootWithAnimation(destination)
        }
    }

    public func pop() {
        executeOperation { [weak self] in
            guard let self = self else {
                NavigationLogger.error("POP - Router is nil, operation cancelled")
                return
            }
            NavigationLogger.debug("POP - Current path: \(path.count)")

            if !path.isEmpty {
                path.removeLast()
                NavigationLogger.debug("POP - Popped. New path: \(path.count)")
            } else {
                NavigationLogger.warning("POP - Path empty, nothing to pop")
            }
        }
    }

    public func popToRoot() {
        executeOperation { [weak self] in
            guard let self = self else { return }
            NavigationLogger.debug("POPTOROOT - Clearing path of \(path.count) items")
            path.removeAll()
            NavigationLogger.debug("POPTOROOT - Path cleared")
        }
    }

    // MARK: - Sheets & Covers
    public func present<Content: View>(@ViewBuilder _ destination: @escaping () -> Content, onDismiss: (() -> Void)? = nil) {
        executeOperation { [weak self] in
            guard let self = self else {
                NavigationLogger.error("PRESENT - Router is nil, operation cancelled")
                return
            }

            guard !isPresenting else {
                printAlreadyPresenting()
                return
            }

            NavigationLogger.debug("PRESENT - hasParent=\(parent != nil) - Setting fullscreen")
            onFullScreenDismiss = onDismiss
            let newRouter = Router(parent: self, root: destination)
            self.fullScreenDestination = newRouter
        }
    }

    public func sheet<Content: View>(@ViewBuilder _ destination: @escaping () -> Content, onDismiss: (() -> Void)? = nil) {
        executeOperation { [weak self] in
            guard let self = self else {
                NavigationLogger.error("SHEET - Router is nil, operation cancelled")
                return
            }

            guard !isPresenting else {
                printAlreadyPresenting()
                return
            }

            NavigationLogger.debug("SHEET - hasParent=\(parent != nil) - Setting sheet")
            onSheetDismiss = onDismiss
            let newRouter = Router(parent: self, root: destination)
            sheetDestination = newRouter
        }
    }

    public func dismiss() {
        executeOperation { [weak self] in
            guard let self = self else {
                NavigationLogger.error("DISMISS - Router is nil, operation cancelled")
                return
            }

            // Silently ignore dismiss if no parent (root view)
            guard parent != nil else {
                return
            }

            NavigationLogger.debug("DISMISS - Dismissing from parent")
            if parent?.sheetDestination != nil {
                parent?.sheetDestination = nil
                NavigationLogger.debug("DISMISS - Cleared parent's sheet")
                return
            }
            if parent?.fullScreenDestination != nil {
                parent?.fullScreenDestination = nil
                NavigationLogger.debug("DISMISS - Cleared parent's fullscreen")
                return
            }
            NavigationLogger.warning("DISMISS - No parent destination to clear")
        }
    }

    public func dismissPresented() {
        executeOperation { [weak self] in
            guard let self = self else {
                NavigationLogger.error("DISMISS_PRESENTED - Router is nil, operation cancelled")
                return
            }

            if sheetDestination != nil {
                sheetDestination?.dismiss()
            } else if fullScreenDestination != nil {
                fullScreenDestination?.dismiss()
            } else {
                NavigationLogger.warning("DISMISS_PRESENTED - No presented view to dismiss")
            }
        }
    }

    public func dismissToRoot() {
        executeOperation { [weak self] in
            guard let self = self else { return }

            sheetDestination = nil
            fullScreenDestination = nil
            if let parent = parent {
                parent.dismissToRoot()
            }
        }
    }
}


extension Router {
    func printAlreadyPresenting() {
        if sheetDestination != nil {
            NavigationLogger.error("PRESENT - Router already presenting a sheet, cannot present another view")
            return
        }

        if fullScreenDestination != nil {
            NavigationLogger.error("PRESENT - Router already presenting a fullscreen cover, cannot present another view")
            return
        }
    }
}
