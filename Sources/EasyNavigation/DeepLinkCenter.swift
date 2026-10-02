//
//  DeepLinkCenter.swift
//  EasyNavigation
//
//  Created by EasyNavigation on 2026-03-16.
//

import SwiftUI

/// Handles deep link URLs by presenting matched views as sheets.
///
/// Deep links are always presented as sheets with their own NavigationStack,
/// ensuring the user's current navigation state is never disrupted.
///
/// Usage:
/// ```swift
/// // 1. Create and configure in your App
/// let deepLinkCenter = DeepLinkCenter()
///
/// // 2. Register URL handler
/// deepLinkCenter.register { url in
///     guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
///         return nil
///     }
///     switch components.path {
///     case "/profile":
///         if let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
///             return ProfileView(userId: id)
///         }
///     case "/settings":
///         return SettingsView()
///     default:
///         return nil
///     }
///     return nil
/// }
///
/// // 3. Connect the router — in the root screen, which reads it with `@Router`
/// .onAppear { deepLinkCenter.setRootRouter(router) }
///
/// // 4. Handle incoming URLs
/// .onOpenURL { url in
///     deepLinkCenter.handle(url)
/// }
/// ```
@Observable
@MainActor
public final class DeepLinkCenter {
    private weak var rootRouter: _Router?
    @ObservationIgnored
    private var handler: (@MainActor @Sendable (URL) -> AnyView?)?
    private var pendingURLs: [URL] = []

    public init() {}

    /// Set the root router used for presenting deep link sheets.
    /// Automatically delivers any pending deep links.
    public func setRootRouter(_ router: Router) {
        self.rootRouter = router.resolved
        deliverPending()
    }

    /// Register a handler that converts URLs to views.
    /// Return `nil` for URLs that should not be handled.
    public func register<Content: View>(
        handler: @escaping @MainActor @Sendable (URL) -> Content?
    ) {
        self.handler = { url in
            if let view = handler(url) {
                return AnyView(view)
            }
            return nil
        }
    }

    /// Handle an incoming deep link URL.
    /// If the router is not ready yet, the URL is queued for later delivery.
    public func handle(_ url: URL) {
        NavigationLogger.debug("DEEPLINK - Received: \(url.absoluteString)")

        guard handler != nil else {
            NavigationLogger.warning("DEEPLINK - No handler registered, queuing URL")
            pendingURLs.append(url)
            return
        }

        guard let rootRouter else {
            NavigationLogger.debug("DEEPLINK - Router not ready, queuing URL")
            pendingURLs.append(url)
            return
        }

        deliver(url, to: rootRouter)
    }

    /// Whether there are pending deep links waiting for router.
    public var hasPendingDeepLinks: Bool {
        !pendingURLs.isEmpty
    }

    /// Number of pending deep links.
    public var pendingCount: Int {
        pendingURLs.count
    }

    /// Clear all pending deep links without delivering them.
    public func clearPending() {
        let count = pendingURLs.count
        pendingURLs.removeAll()
        NavigationLogger.debug("DEEPLINK - Cleared \(count) pending URLs")
    }

    // MARK: - Private

    private func deliver(_ url: URL, to router: _Router) {
        guard let view = handler?(url) else {
            NavigationLogger.debug("DEEPLINK - Handler returned nil for: \(url.absoluteString)")
            return
        }

        // Dismiss any existing presentation to make room for deep link.
        // Fire the existing onDismiss callbacks (instead of silently dropping them)
        // before replacing the destination.
        if router.isPresenting {
            router.fireSheetDismiss()
            router.fireFullScreenDismiss()
            router.sheetDestination = nil
            router.fullScreenDestination = nil
            NavigationLogger.debug("DEEPLINK - Dismissed existing presentation")
        }

        // Present as sheet with its own NavigationStack
        let newRouter = _Router(parent: router) { view }
        router.sheetDestination = newRouter
        NavigationLogger.debug("DEEPLINK - Presented sheet for: \(url.absoluteString)")
    }

    private func deliverPending() {
        guard let rootRouter, !pendingURLs.isEmpty else { return }

        // Only deliver the most recent pending URL — older ones are stale
        let latestURL = pendingURLs.last!
        let count = pendingURLs.count
        pendingURLs.removeAll()

        NavigationLogger.debug("DEEPLINK - Delivering latest of \(count) pending URL(s)")
        deliver(latestURL, to: rootRouter)
    }
}
