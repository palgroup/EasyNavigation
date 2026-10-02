//
//  Router.swift
//  EasyNavigation
//
//  How a view navigates:
//
//      @Router private var router
//
//      router.push { NoteDetailBuilder.build(id: note.id) }
//      router.sheet(onDismiss: reload) { NoteEditorBuilder.build() }
//      router.pop()
//
//  The destination closures run on the main actor, so a main-actor builder
//  is called in them directly.
//
//  `Router` is the property wrapper and its own value. It reads the nearest
//  navigation stack's `_Router` from the environment and passes every call on
//  to it. The class is internal, so a view has no other way to read it.
//
//  Outside every navigation wrapper it does not crash in an Xcode preview: the
//  screen gets a detached router, renders, and navigating from it does
//  nothing. In the app it stops with a message that names the fix. See
//  `MissingRouter`.
//
//  A container that needs a stack's state from outside the stack owns its
//  router instead:
//
//      @State private var router = Router { HomeScreen() }
//
//      ViewNavigationWrapper(router: router)
//          .overlay { if router.isPresenting { … } }
//
//  A view shown outside every stack (a window overlay) gets the router as a
//  value: pass `router` to its initializer.
//

import SwiftUI

@propertyWrapper
public struct Router: DynamicProperty, Sendable {
    @Environment(_Router.self)
    private var environmentRouter: _Router?

    /// A router this value owns or was handed (`Router { … }`,
    /// `Navigation.router`); when it is `nil` the environment's is used.
    private let heldRouter: _Router?

    /// Reads the router of the navigation stack the view is in.
    public init() {
        heldRouter = nil
    }

    /// The router of a new stack, owned by the caller and shown with
    /// `ViewNavigationWrapper(router:)`.
    @MainActor
    public init<Content: View>(showsNavigationBar: Bool = false, @ViewBuilder root: @escaping () -> Content) {
        heldRouter = _Router(showsNavigationBar: showsNavigationBar, root: root)
    }

    init(_ router: _Router) {
        heldRouter = router
    }

    @MainActor
    public var wrappedValue: Router {
        self
    }

    /// Resolved when a call is made, not when the wrapper is created: a view
    /// that only declares `@Router` renders anywhere, and the missing-router
    /// handling runs when it navigates.
    @MainActor
    var resolved: _Router {
        resolved(isRunningForPreviews: MissingRouter.isRunningForPreviews)
    }

    @MainActor
    func resolved(isRunningForPreviews: Bool) -> _Router {
        heldRouter ?? MissingRouter.resolve(environmentRouter, in: "@Router", isRunningForPreviews: isRunningForPreviews)
    }
}

// MARK: - State

@MainActor
extension Router {
    /// The pushed screens, root not included.
    public var path: [DestinationWrapper] {
        resolved.path
    }

    public var isPresenting: Bool {
        resolved.isPresenting
    }

    /// Whether the screen on top allows the back swipe.
    public var isBackSwipeAllowed: Bool {
        resolved.isBackSwipeAllowed
    }
}

// MARK: - Push

@MainActor
extension Router {
    public func push<Content: View>(
        allowBackSwipe: Bool = true,
        showsNavigationBar: Bool = false,
        @ViewBuilder _ destination: @escaping @MainActor @Sendable () -> Content
    ) {
        resolved.push(allowBackSwipe: allowBackSwipe, showsNavigationBar: showsNavigationBar, destination)
    }

    /// Replaces the screen on top (the root when nothing is pushed).
    public func replacingPush<Content: View>(@ViewBuilder _ destination: @escaping @MainActor @Sendable () -> Content) {
        resolved.replacingPush(destination)
    }

    /// Clears the path and makes `destination` the new root.
    public func removeAllPush<Content: View>(@ViewBuilder _ destination: @escaping @MainActor @Sendable () -> Content) {
        resolved.removeAllPush(destination)
    }

    public func pop() {
        resolved.pop()
    }

    public func popToRoot() {
        resolved.popToRoot()
    }
}

// MARK: - Sheets and covers

@MainActor
extension Router {
    public func sheet<Content: View>(
        configuration: PresentationConfiguration = .init(),
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder _ destination: @escaping @MainActor @Sendable () -> Content
    ) {
        resolved.sheet(configuration: configuration, onDismiss: onDismiss, destination)
    }

    /// Presents full screen.
    public func present<Content: View>(
        configuration: PresentationConfiguration = .init(),
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder _ destination: @escaping @MainActor @Sendable () -> Content
    ) {
        resolved.present(configuration: configuration, onDismiss: onDismiss, destination)
    }

    /// Dismisses the sheet or cover this view is in.
    public func dismiss() {
        resolved.dismiss()
    }

    /// Dismisses the sheet or cover this view presented.
    public func dismissPresented() {
        resolved.dismissPresented()
    }

    /// Dismisses every presentation, keeping each level's pushed screens.
    public func dismissToRoot() {
        resolved.dismissToRoot()
    }

    /// Dismisses every presentation and clears every push: back to the app's root.
    public func resetToRoot() {
        resolved.resetToRoot()
    }
}
