//
//  _Router.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//
//  The navigation state of one stack: its pushed path and what it presents.
//  Internal — a view reaches it only through `@Router`, so there is no
//  `@Environment(…self)` to write by hand and no way to read it without the
//  missing-router handling (see `Router.swift`, `MissingRouter.swift`).
//

import SwiftUI

@MainActor
@Observable
final class _Router: Identifiable {
    let id = UUID().uuidString
    /// Deferred root view construction — only evaluated when SwiftUI renders
    private var _makeRoot: @MainActor @Sendable () -> AnyView
    var path: [DestinationWrapper] = []
    var fullScreenDestination: _Router?
    @ObservationIgnored
    var onFullScreenDismiss: (() -> Void)?
    var sheetDestination: _Router?
    @ObservationIgnored
    var onSheetDismiss: (() -> Void)?

    /// Whether this router's ROOT view shows the native navigation bar.
    /// Default `false` preserves the library's custom-header behavior; set `true`
    /// to get native `.navigationTitle`/`.toolbar`/back button back for the root.
    @ObservationIgnored
    let showsNavigationBar: Bool

    /// How this router was presented (sheet detents, drag indicator, interactive
    /// dismissal). Empty for the app's root router; set by the presenting parent.
    @ObservationIgnored
    var presentationConfiguration: PresentationConfiguration = .init()

    /// A presentation requested while another was already in flight. Drained by the
    /// view layer once the current presentation finishes dismissing (see `drainPendingPresentation`).
    @ObservationIgnored
    private var pendingPresentation: (() -> Void)?

    // Cached, immutable navigation-info objects — avoids re-allocating a fresh
    // @Observable instance on every body render, which would churn the environment
    // identity and force every consumer to re-render.
    @ObservationIgnored private var _rootNavigationInformation: NavigationInformations?
    @ObservationIgnored private var _pushedNavigationInformation: NavigationInformations?

    var rootViewID: UUID = UUID()

    /// Concrete wrapper for root view rendering — gives SwiftUI stable structural identity
    var rootView: RootContentView {
        RootContentView(render: _makeRoot)
    }

    @ObservationIgnored
    weak var parent: _Router?

    // AsyncStream-based serial operation processor
    @ObservationIgnored
    private var navigationContinuation: AsyncStream<@MainActor @Sendable () -> Void>.Continuation?

    @ObservationIgnored
    private var processingTask: Task<Void, Never>?

    var isPresenting: Bool {
        fullScreenDestination != nil || sheetDestination != nil
    }

    /// Whether the current top-of-stack view allows back swipe.
    /// Returns true when path is empty (root views always allow).
    var isBackSwipeAllowed: Bool {
        path.last?.allowsBackSwipe ?? true
    }

    init<Content: View>(
        parent: _Router? = nil,
        showsNavigationBar: Bool = false,
        @ViewBuilder root: @escaping () -> Content
    ) {
        self.parent = parent
        self.showsNavigationBar = showsNavigationBar
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
    func cleanup() {
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
        pendingPresentation = nil

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
    func push<Content: View>(allowBackSwipe: Bool = true, showsNavigationBar: Bool = false, @ViewBuilder _ destination: @escaping @Sendable () -> Content) {
        let dest = destination
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("PUSH - Router is nil, operation cancelled")
                return
            }
            NavigationLogger.debug("PUSH - Current path count: \(self.path.count)")

            let wrapper = DestinationWrapper(
                allowsBackSwipe: allowBackSwipe,
                showsNavigationBar: showsNavigationBar,
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

    func replacingPush<Content: View>(@ViewBuilder _ destination: @escaping @Sendable () -> Content) {
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
                // Replace the current top in place — a single mutation.
                // Avoids the transient [A, B, C, D] state (double animation) of an
                // append-then-remove, and always targets the *live* top index, so it
                // stays correct even if SwiftUI mutated the path (system back / swipe)
                // between queued operations.
                self.path[self.path.count - 1] = DestinationWrapper(content: dest)
                NavigationLogger.debug("replacingPush - replaced top in place, path count=\(self.path.count)")
            }
        }
    }

    func removeAllPush<Content: View>(@ViewBuilder _ destination: @escaping @Sendable () -> Content) {
        executeOperation { [weak self] in
            self?.replaceRootWithAnimation(destination)
        }
    }

    func pop() {
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

    func popToRoot() {
        executeOperation { [weak self] in
            guard let self else { return }
            NavigationLogger.debug("POPTOROOT - Clearing path of \(self.path.count) items")
            self.path.removeAll()
            NavigationLogger.debug("POPTOROOT - Path cleared")
        }
    }

    // MARK: - Sheets & Covers
    func present<Content: View>(
        configuration: PresentationConfiguration = .init(),
        @ViewBuilder _ destination: @escaping @Sendable () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        let dest = destination
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("PRESENT - Router is nil, operation cancelled")
                return
            }

            guard !self.isPresenting else {
                // Don't silently drop the request (and its onDismiss) — queue it to
                // fire automatically once the current presentation is dismissed.
                NavigationLogger.debug("PRESENT - busy, queuing until current presentation dismisses")
                self.pendingPresentation = { [weak self] in
                    self?.present(configuration: configuration, dest, onDismiss: onDismiss)
                }
                return
            }

            NavigationLogger.debug("PRESENT - hasParent=\(self.parent != nil) - Setting fullscreen")
            self.onFullScreenDismiss = onDismiss
            let newRouter = _Router(parent: self, root: dest)
            newRouter.presentationConfiguration = configuration
            self.fullScreenDestination = newRouter
        }
    }

    func sheet<Content: View>(
        configuration: PresentationConfiguration = .init(),
        @ViewBuilder _ destination: @escaping @Sendable () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        let dest = destination
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("SHEET - Router is nil, operation cancelled")
                return
            }

            guard !self.isPresenting else {
                // Don't silently drop the request (and its onDismiss) — queue it to
                // fire automatically once the current presentation is dismissed.
                NavigationLogger.debug("SHEET - busy, queuing until current presentation dismisses")
                self.pendingPresentation = { [weak self] in
                    self?.sheet(configuration: configuration, dest, onDismiss: onDismiss)
                }
                return
            }

            NavigationLogger.debug("SHEET - hasParent=\(self.parent != nil) - Setting sheet")
            self.onSheetDismiss = onDismiss
            let newRouter = _Router(parent: self, root: dest)
            newRouter.presentationConfiguration = configuration
            self.sheetDestination = newRouter
        }
    }

    func dismiss() {
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

    func dismissPresented() {
        executeOperation { [weak self] in
            guard let self else {
                NavigationLogger.error("DISMISS_PRESENTED - Router is nil, operation cancelled")
                return
            }

            // Clear the destination we own directly, on our own queue. The view layer
            // fires the matching onDismiss and drains any queued presentation. (Previously
            // this hopped onto the child's separate queue, which could race a replacement.)
            if self.sheetDestination != nil {
                self.sheetDestination = nil
                NavigationLogger.debug("DISMISS_PRESENTED - Cleared own sheet")
            } else if self.fullScreenDestination != nil {
                self.fullScreenDestination = nil
                NavigationLogger.debug("DISMISS_PRESENTED - Cleared own fullscreen")
            } else {
                NavigationLogger.warning("DISMISS_PRESENTED - No presented view to dismiss")
            }
        }
    }

    func dismissToRoot() {
        executeOperation { [weak self] in
            guard let self else { return }

            // Walk to the absolute root and clear in a SINGLE operation (mirrors
            // resetToRoot) instead of cascading across each ancestor's separate queue,
            // which could interleave with other queued ops. Child routers deallocate
            // automatically when the root's destination becomes nil.
            var root: _Router = self
            while let parent = root.parent { root = parent }

            root.fireSubtreeDismissCallbacks()
            root.pendingPresentation = nil
            root.sheetDestination = nil
            root.fullScreenDestination = nil
            // NOTE: unlike resetToRoot, each level's push path is intentionally preserved.
        }
    }

    /// Nuclear reset — dismisses ALL presentations AND clears ALL pushes.
    /// Walks up the entire parent chain, at each level:
    /// 1. Clears sheetDestination and fullScreenDestination
    /// 2. Clears the push path
    /// Then continues to the parent until reaching the root router.
    /// One call = back to home screen, no matter how deep you are.
    /// Nuclear reset — dismisses ALL presentations AND clears ALL pushes.
    /// Walks up to the root router first, then clears from the top down.
    /// Child routers are deallocated automatically when parent's destination becomes nil.
    /// Only one dismiss animation plays (the topmost presentation).
    func resetToRoot() {
        executeOperation { [weak self] in
            guard let self else { return }
            NavigationLogger.debug("RESET_TO_ROOT - Starting full reset")

            // Find the absolute root router
            var root: _Router = self
            while let parent = root.parent {
                root = parent
            }

            // Fire any pending dismiss callbacks across the whole presented subtree
            // (exactly-once) before tearing it down, so they aren't silently dropped.
            root.fireSubtreeDismissCallbacks()
            root.pendingPresentation = nil

            // Clear from root — child routers dealloc automatically
            root.sheetDestination = nil
            root.fullScreenDestination = nil
            root.path.removeAll()

            NavigationLogger.debug("RESET_TO_ROOT - Reset complete from root")
        }
    }
}


// MARK: - ViewDestination Support
extension _Router {
    /// Push a ViewDestination-conforming route (enum routing).
    ///
    /// `body` is evaluated here on the main actor (this method is `@MainActor`) and
    /// the resulting view value is handed to the `@Sendable` builder closure. The
    /// `nonisolated(unsafe)` is sound by construction: the view is built on the main
    /// actor and only ever read back on the main actor at render time.
    func push<D: ViewDestination>(_ destination: D, allowBackSwipe: Bool = true, showsNavigationBar: Bool = false) {
        nonisolated(unsafe) let body = destination.body
        push(allowBackSwipe: allowBackSwipe, showsNavigationBar: showsNavigationBar) { body }
    }

    /// Present a ViewDestination-conforming route as fullscreen
    func present<D: ViewDestination>(_ destination: D, configuration: PresentationConfiguration = .init(), onDismiss: (() -> Void)? = nil) {
        nonisolated(unsafe) let body = destination.body
        present(configuration: configuration, { body }, onDismiss: onDismiss)
    }

    /// Present a ViewDestination-conforming route as sheet
    func sheet<D: ViewDestination>(_ destination: D, configuration: PresentationConfiguration = .init(), onDismiss: (() -> Void)? = nil) {
        nonisolated(unsafe) let body = destination.body
        sheet(configuration: configuration, { body }, onDismiss: onDismiss)
    }
}

// MARK: - Navigation information (cached)
extension _Router {
    /// Returns the cached, immutable `NavigationInformations` for this router.
    /// Cached so the environment value keeps a stable identity across body renders
    /// (a fresh instance every render would invalidate every consumer needlessly).
    func navigationInformation(isPushed: Bool) -> NavigationInformations {
        if isPushed {
            if let info = _pushedNavigationInformation { return info }
            let info = makeNavigationInformation(isPushed: true)
            _pushedNavigationInformation = info
            return info
        } else {
            if let info = _rootNavigationInformation { return info }
            let info = makeNavigationInformation(isPushed: false)
            _rootNavigationInformation = info
            return info
        }
    }

    private func makeNavigationInformation(isPushed: Bool) -> NavigationInformations {
        NavigationInformations(
            isPushed: isPushed,
            isPresenting: parent != nil,
            navigationType: parent == nil
                ? .root
                : (parent?.fullScreenDestination != nil ? .present : .sheet)
        )
    }
}

// MARK: - Dismiss callbacks & pending presentations
extension _Router {
    /// Fires and clears the full-screen dismiss callback. Idempotent: safe to call
    /// from both the programmatic teardown path and SwiftUI's `onDismiss`, so the
    /// user's callback runs exactly once regardless of how the cover was dismissed.
    func fireFullScreenDismiss() {
        let callback = onFullScreenDismiss
        onFullScreenDismiss = nil
        callback?()
    }

    /// Fires and clears the sheet dismiss callback. Idempotent (see `fireFullScreenDismiss`).
    func fireSheetDismiss() {
        let callback = onSheetDismiss
        onSheetDismiss = nil
        callback?()
    }

    /// Fires dismiss callbacks for the entire presented subtree before a bulk teardown
    /// (resetToRoot / dismissToRoot), so no level's `onDismiss` is silently dropped.
    func fireSubtreeDismissCallbacks() {
        fullScreenDestination?.fireSubtreeDismissCallbacks()
        sheetDestination?.fireSubtreeDismissCallbacks()
        fireFullScreenDismiss()
        fireSheetDismiss()
    }

    /// Presents a request that was queued while another presentation was in flight.
    /// Called by the view layer once the current presentation has fully dismissed.
    func drainPendingPresentation() {
        guard let pending = pendingPresentation else { return }
        pendingPresentation = nil
        pending()
    }
}

/// Concrete View type for SwiftUI structural identity at the root level.
struct RootContentView: View {
    let render: @MainActor @Sendable () -> AnyView

    var body: some View {
        render()
    }
}
