//
//  Router.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import SwiftUI

@MainActor
@Observable
public class Router: Identifiable, Sendable {
    public let id = UUID().uuidString
    /// Deferred root view construction — only evaluated when SwiftUI renders
    private var _makeRoot: @MainActor @Sendable () -> AnyView
    public internal(set) var path: [DestinationWrapper] = []
    var fullScreenDestination: Router?
    @ObservationIgnored
    var onFullScreenDismiss: (() -> Void)?
    var sheetDestination: Router?
    @ObservationIgnored
    var onSheetDismiss: (() -> Void)?

    var rootViewID: UUID = UUID()

    /// Concrete wrapper for root view rendering — gives SwiftUI stable structural identity
    var rootView: RootContentView {
        RootContentView(render: _makeRoot)
    }

    @ObservationIgnored
    weak var parent: Router?

    // AsyncStream-based serial operation processor
    @ObservationIgnored
    private var navigationContinuation: AsyncStream<@MainActor @Sendable () -> Void>.Continuation?

    @ObservationIgnored
    private var processingTask: Task<Void, Never>?

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
        self._makeRoot = { AnyView(root()) }
        self.rootViewID = UUID()
        startOperationProcessor()
    }

    /// Starts the serial navigation operation processor.
    /// All navigation ops are queued and executed one at a time on @MainActor
    /// with a yield between each to let SwiftUI commit state changes.
    private func startOperationProcessor() {
        let (stream, continuation) = AsyncStream<@MainActor @Sendable () -> Void>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.navigationContinuation = continuation

        processingTask = Task { [weak self] in
            for await operation in stream {
                guard self != nil else { break }
                operation()
                await Task.yield()
            }
        }
    }

    /// Queues a navigation operation for serial execution.
    /// Operations execute in FIFO order on @MainActor.
    private func executeOperation(_ operation: @escaping @MainActor @Sendable () -> Void) {
        navigationContinuation?.yield(operation)
    }

    /// Cleanup all router references and destinations
    /// Call this before replacing root views to break retain cycles
    public func cleanup() {
        NavigationLogger.debug("CLEANUP - Starting cleanup")

        // Terminate the operation stream
        navigationContinuation?.finish()
        processingTask?.cancel()

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
        self._makeRoot = { AnyView(EmptyView()) }

        NavigationLogger.debug("CLEANUP - Complete")
    }

    deinit {
        navigationContinuation?.finish()
        processingTask?.cancel()
        NavigationLogger.debug("Router deiniting")
    }

    // MARK: - Navigation API
    public func push<Content: View>(allowBackSwipe: Bool = true, @ViewBuilder _ destination: @escaping @Sendable () -> Content) {
        let dest = destination
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("PUSH - Router is nil, operation cancelled")
                return
            }
            NavigationLogger.debug("PUSH - Current path count: \(self.path.count)")

            let wrapper = DestinationWrapper(
                allowsBackSwipe: allowBackSwipe,
                content: dest
            )
            self.path.append(wrapper)
            NavigationLogger.debug("PUSH - Pushed. New path count: \(self.path.count)")
        }
    }

    @MainActor
    private func replaceRootWithAnimation<Content: View>(_ newRootViewGenerator: @escaping () -> Content) {
        let newRootID = UUID()
        withAnimation(.default) {
            self._makeRoot = { AnyView(newRootViewGenerator()) }
            self.rootViewID = newRootID
            self.path.removeAll()
        }
    }

    public func replacingPush<Content: View>(@ViewBuilder _ destination: @escaping @Sendable () -> Content) {
        let dest = destination
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("replacingPush - Router is nil")
                return
            }

            if self.path.isEmpty {
                // No pushed views — replace the root
                self.replaceRootWithAnimation(dest)
                NavigationLogger.debug("replacingPush - replaced root (path was empty)")
            } else {
                // Push new view, then remove the old top
                // Before append: path = [A, B, C] (C is current top)
                // After append:  path = [A, B, C, D]
                // Remove at count-2: removes C → path = [A, B, D] ✓
                self.path.append(DestinationWrapper(content: dest))
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
            guard let self else {
                NavigationLogger.error("POP - Router is nil, operation cancelled")
                return
            }
            NavigationLogger.debug("POP - Current path: \(self.path.count)")

            if !self.path.isEmpty {
                self.path.removeLast()
                NavigationLogger.debug("POP - Popped. New path: \(self.path.count)")
            } else {
                NavigationLogger.warning("POP - Path empty, nothing to pop")
            }
        }
    }

    public func popToRoot() {
        executeOperation { [weak self] in
            guard let self else { return }
            NavigationLogger.debug("POPTOROOT - Clearing path of \(self.path.count) items")
            self.path.removeAll()
            NavigationLogger.debug("POPTOROOT - Path cleared")
        }
    }

    // MARK: - Sheets & Covers
    public func present<Content: View>(@ViewBuilder _ destination: @escaping () -> Content, onDismiss: (() -> Void)? = nil) {
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("PRESENT - Router is nil, operation cancelled")
                return
            }

            guard !self.isPresenting else {
                self.logAlreadyPresenting()
                return
            }

            NavigationLogger.debug("PRESENT - hasParent=\(self.parent != nil) - Setting fullscreen")
            self.onFullScreenDismiss = onDismiss
            let newRouter = Router(parent: self, root: destination)
            self.fullScreenDestination = newRouter
        }
    }

    public func sheet<Content: View>(@ViewBuilder _ destination: @escaping () -> Content, onDismiss: (() -> Void)? = nil) {
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("SHEET - Router is nil, operation cancelled")
                return
            }

            guard !self.isPresenting else {
                self.logAlreadyPresenting()
                return
            }

            NavigationLogger.debug("SHEET - hasParent=\(self.parent != nil) - Setting sheet")
            self.onSheetDismiss = onDismiss
            let newRouter = Router(parent: self, root: destination)
            self.sheetDestination = newRouter
        }
    }

    public func dismiss() {
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("DISMISS - Router is nil, operation cancelled")
                return
            }

            // Silently ignore dismiss if no parent (root view)
            guard self.parent != nil else {
                return
            }

            NavigationLogger.debug("DISMISS - Dismissing from parent")
            if self.parent?.sheetDestination != nil {
                self.parent?.sheetDestination = nil
                NavigationLogger.debug("DISMISS - Cleared parent's sheet")
                return
            }
            if self.parent?.fullScreenDestination != nil {
                self.parent?.fullScreenDestination = nil
                NavigationLogger.debug("DISMISS - Cleared parent's fullscreen")
                return
            }
            NavigationLogger.warning("DISMISS - No parent destination to clear")
        }
    }

    public func dismissPresented() {
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("DISMISS_PRESENTED - Router is nil, operation cancelled")
                return
            }

            if self.sheetDestination != nil {
                self.sheetDestination?.dismiss()
            } else if self.fullScreenDestination != nil {
                self.fullScreenDestination?.dismiss()
            } else {
                NavigationLogger.warning("DISMISS_PRESENTED - No presented view to dismiss")
            }
        }
    }

    public func dismissToRoot() {
        executeOperation { [weak self] in
            guard let self else { return }

            self.sheetDestination = nil
            self.fullScreenDestination = nil
            if let parent = self.parent {
                parent.dismissToRoot()
            }
        }
    }

    /// Nuclear reset — dismisses ALL presentations AND clears ALL pushes.
    /// Walks up the entire parent chain, at each level:
    /// 1. Clears sheetDestination and fullScreenDestination
    /// 2. Clears the push path
    /// Then continues to the parent until reaching the root router.
    /// One call = back to home screen, no matter how deep you are.
    public func resetToRoot() {
        executeOperation { [weak self] in
            guard let self else { return }
            NavigationLogger.debug("RESET_TO_ROOT - Starting full reset")

            // Disable both UIKit and SwiftUI animations for instant reset
            UIView.setAnimationsEnabled(false)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.sheetDestination = nil
                self.fullScreenDestination = nil
                self.path.removeAll()
            }

            // Re-enable after next runloop tick to ensure dismissals complete
            DispatchQueue.main.async {
                UIView.setAnimationsEnabled(true)
            }

            if let parent = self.parent {
                parent.resetToRoot()
            } else {
                NavigationLogger.debug("RESET_TO_ROOT - Reached root router, reset complete")
            }
        }
    }
}


// MARK: - ViewDestination Support
extension Router {
    /// Push a ViewDestination-conforming route (enum routing)
    public func push<D: ViewDestination>(_ destination: D, allowBackSwipe: Bool = true) {
        nonisolated(unsafe) let body = destination.body
        push(allowBackSwipe: allowBackSwipe) { body }
    }

    /// Present a ViewDestination-conforming route as fullscreen
    public func present<D: ViewDestination>(_ destination: D, onDismiss: (() -> Void)? = nil) {
        nonisolated(unsafe) let body = destination.body
        present({ body }, onDismiss: onDismiss)
    }

    /// Present a ViewDestination-conforming route as sheet
    public func sheet<D: ViewDestination>(_ destination: D, onDismiss: (() -> Void)? = nil) {
        nonisolated(unsafe) let body = destination.body
        sheet({ body }, onDismiss: onDismiss)
    }
}

extension Router {
    fileprivate func logAlreadyPresenting() {
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

/// Concrete View type for SwiftUI structural identity at the root level.
struct RootContentView: View {
    let render: @MainActor @Sendable () -> AnyView

    var body: some View {
        render()
    }
}
