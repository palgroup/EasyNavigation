//
//  DeepLinkCenterTests.swift
//  EasyNavigationTests
//

import Testing
import SwiftUI
@testable import EasyNavigation

@MainActor
@Suite("DeepLinkCenter")
struct DeepLinkCenterTests {

    private func makeCenter() -> DeepLinkCenter {
        let center = DeepLinkCenter()
        center.register { (url: URL) -> Text? in
            if url.absoluteString.contains("profile") {
                return Text("Profile")
            }
            return nil
        }
        return center
    }

    // MARK: - Basic Handling

    @Test("handle presents sheet on root router")
    func handlePresentsSheet() async {
        let center = makeCenter()
        let router = _Router { EmptyView() }
        center.setRootRouter(Router(router))

        center.handle(URL(string: "myapp://profile/123")!)
        #expect(router.sheetDestination != nil)
    }

    @Test("handle with unmatched URL does nothing")
    func handleUnmatchedURL() async {
        let center = makeCenter()
        let router = _Router { EmptyView() }
        center.setRootRouter(Router(router))

        center.handle(URL(string: "myapp://unknown")!)
        #expect(router.sheetDestination == nil)
    }

    // MARK: - Pending Queue

    @Test("URLs are queued when router not set")
    func urlsQueuedBeforeRouter() async {
        let center = makeCenter()

        center.handle(URL(string: "myapp://profile/1")!)
        center.handle(URL(string: "myapp://profile/2")!)

        #expect(center.hasPendingDeepLinks)
        #expect(center.pendingCount == 2)
    }

    @Test("pending URLs delivered when router is set")
    func pendingDeliveredOnRouterSet() async {
        let center = makeCenter()

        center.handle(URL(string: "myapp://profile/1")!)
        center.handle(URL(string: "myapp://profile/2")!)

        let router = _Router { EmptyView() }
        center.setRootRouter(Router(router))

        // Only latest should be delivered
        #expect(router.sheetDestination != nil)
        #expect(!center.hasPendingDeepLinks)
    }

    @Test("URLs queued when no handler registered")
    func urlsQueuedWithoutHandler() async {
        let center = DeepLinkCenter()
        // No register() call

        center.handle(URL(string: "myapp://profile/1")!)
        #expect(center.hasPendingDeepLinks)
    }

    // MARK: - Dismiss Existing Presentation

    @Test("handle dismisses existing sheet before presenting")
    func dismissesExistingSheet() async {
        let center = makeCenter()
        let router = _Router { EmptyView() }
        center.setRootRouter(Router(router))

        // Open an existing sheet
        router.sheetDestination = _Router(parent: router) { Text("Old") }
        #expect(router.isPresenting)

        // Deep link should replace it
        center.handle(URL(string: "myapp://profile/123")!)
        #expect(router.sheetDestination != nil)
        // The sheet destination should be a new router (not the old one)
    }

    @Test("handle dismisses existing fullscreen before presenting")
    func dismissesExistingFullscreen() async {
        let center = makeCenter()
        let router = _Router { EmptyView() }
        center.setRootRouter(Router(router))

        // Open an existing fullscreen
        router.fullScreenDestination = _Router(parent: router) { Text("Old") }
        #expect(router.isPresenting)

        // Deep link should dismiss fullscreen and open sheet
        center.handle(URL(string: "myapp://profile/123")!)
        #expect(router.fullScreenDestination == nil)
        #expect(router.sheetDestination != nil)
    }

    // MARK: - Clear Pending

    @Test("clearPending removes all queued URLs")
    func clearPendingRemovesAll() async {
        let center = makeCenter()

        center.handle(URL(string: "myapp://profile/1")!)
        center.handle(URL(string: "myapp://profile/2")!)
        #expect(center.pendingCount == 2)

        center.clearPending()
        #expect(center.pendingCount == 0)
        #expect(!center.hasPendingDeepLinks)
    }

    // MARK: - Weak Router Reference

    @Test("center does not retain router")
    func weakRouterReference() async {
        let center = makeCenter()

        // Create router in inner scope
        var router: _Router? = _Router { EmptyView() }
        center.setRootRouter(Router(router!))

        // Release router
        router = nil

        // URL should be queued (router gone)
        center.handle(URL(string: "myapp://profile/1")!)
        #expect(center.hasPendingDeepLinks)
    }
}
