//
//  RouterPropertyWrapperTests.swift
//  EasyNavigationTests
//
//  `Router` is the public face of the internal `_Router`: it must pass every
//  call on unchanged, read the stack the view is in, own a stack when asked
//  to, and — outside every stack — fall back to the detached router in a
//  preview.
//

import Testing
import SwiftUI
import UIKit
@testable import EasyNavigation

// Serialized: two windows shown at once by parallel tests do not both get
// their bodies evaluated.
@Suite("@Router", .serialized)
@MainActor
struct RouterPropertyWrapperTests {

    // MARK: - Pushes

    @Test("A closure push goes to the router, with its options")
    func closurePush() async {
        let (router, base) = makeRouter()
        router.push(allowBackSwipe: false, showsNavigationBar: true) { Text("A") }
        await waitForRouterOperations()
        #expect(base.path.count == 1)
        #expect(router.path.count == 1)
        #expect(base.path.last?.allowsBackSwipe == false)
        #expect(base.path.last?.showsNavigationBar == true)
        #expect(router.isBackSwipeAllowed == false)
    }

    @Test("A builder push goes to the router, with its options")
    func builderPush() async {
        let (router, base) = makeRouter()
        router.push(allowBackSwipe: false, showsNavigationBar: true) { ProbeBuilder.build() }
        await waitForRouterOperations()
        #expect(base.path.count == 1)
        #expect(base.path.last?.allowsBackSwipe == false)
        #expect(base.path.last?.showsNavigationBar == true)
    }

    @Test("pop removes the top screen, popToRoot all of them")
    func popAndPopToRoot() async {
        let (router, base) = makeRouter()
        router.push { ProbeBuilder.build() }
        router.push { ProbeBuilder.build() }
        router.push { ProbeBuilder.build() }
        await waitForRouterOperations(count: 3)
        router.pop()
        await waitForRouterOperations()
        #expect(base.path.count == 2)
        router.popToRoot()
        await waitForRouterOperations()
        #expect(base.path.isEmpty)
    }

    @Test("replacingPush replaces the top screen in place")
    func replacingPush() async {
        let (router, base) = makeRouter()
        router.push { ProbeBuilder.build() }
        router.push { ProbeBuilder.build() }
        await waitForRouterOperations(count: 2)
        let top = base.path.last?.id
        router.replacingPush { ProbeBuilder.build() }
        await waitForRouterOperations()
        #expect(base.path.count == 2)
        #expect(base.path.last?.id != top)
    }

    @Test("removeAllPush clears the path and replaces the root")
    func removeAllPush() async {
        let (router, base) = makeRouter()
        router.push { ProbeBuilder.build() }
        await waitForRouterOperations()
        let root = base.rootViewID
        router.removeAllPush { ProbeBuilder.build() }
        await waitForRouterOperations()
        #expect(base.path.isEmpty)
        #expect(base.rootViewID != root)
    }

    // MARK: - Sheets and covers

    @Test("A builder sheet is a sheet, with its configuration and onDismiss")
    func builderSheet() async {
        let (router, base) = makeRouter()
        var dismissed = false
        router.sheet(configuration: .init(interactiveDismissDisabled: true), onDismiss: { dismissed = true }) { ProbeBuilder.build() }
        await waitForRouterOperations()
        #expect(base.sheetDestination != nil)
        #expect(base.fullScreenDestination == nil)
        #expect(base.sheetDestination?.presentationConfiguration.interactiveDismissDisabled == true)
        #expect(router.isPresenting)
        base.fireSheetDismiss()
        #expect(dismissed)
    }

    @Test("A closure sheet is a sheet, with its configuration and onDismiss")
    func closureSheet() async {
        let (router, base) = makeRouter()
        var dismissed = false
        router.sheet(configuration: .init(interactiveDismissDisabled: true), onDismiss: { dismissed = true }) { Text("S") }
        await waitForRouterOperations()
        #expect(base.sheetDestination != nil)
        #expect(base.fullScreenDestination == nil)
        #expect(base.sheetDestination?.presentationConfiguration.interactiveDismissDisabled == true)
        base.fireSheetDismiss()
        #expect(dismissed)
    }

    @Test("A builder present is a full-screen cover, with its configuration and onDismiss")
    func builderPresent() async {
        let (router, base) = makeRouter()
        var dismissed = false
        router.present(configuration: .init(interactiveDismissDisabled: true), onDismiss: { dismissed = true }) { ProbeBuilder.build() }
        await waitForRouterOperations()
        #expect(base.fullScreenDestination != nil)
        #expect(base.sheetDestination == nil)
        #expect(base.fullScreenDestination?.presentationConfiguration.interactiveDismissDisabled == true)
        base.fireFullScreenDismiss()
        #expect(dismissed)
    }

    @Test("A closure present is a full-screen cover, with its configuration and onDismiss")
    func closurePresent() async {
        let (router, base) = makeRouter()
        var dismissed = false
        router.present(configuration: .init(interactiveDismissDisabled: true), onDismiss: { dismissed = true }) { Text("P") }
        await waitForRouterOperations()
        #expect(base.fullScreenDestination != nil)
        #expect(base.sheetDestination == nil)
        #expect(base.fullScreenDestination?.presentationConfiguration.interactiveDismissDisabled == true)
        base.fireFullScreenDismiss()
        #expect(dismissed)
    }

    @Test("dismissPresented closes what this router presented")
    func dismissPresented() async {
        let (router, base) = makeRouter()
        router.sheet { ProbeBuilder.build() }
        await waitForRouterOperations()
        router.dismissPresented()
        await waitForRouterOperations()
        #expect(base.sheetDestination == nil)
        #expect(router.isPresenting == false)
    }

    @Test("dismiss closes the presentation this router is in")
    func dismiss() async throws {
        let (router, base) = makeRouter()
        router.sheet { ProbeBuilder.build() }
        await waitForRouterOperations()
        let child = try #require(base.sheetDestination)
        Router(child).dismiss()
        await waitForRouterOperations()
        #expect(base.sheetDestination == nil)
    }

    @Test("dismissToRoot closes every presentation and keeps the pushes")
    func dismissToRoot() async throws {
        let (router, base) = makeRouter()
        router.push { ProbeBuilder.build() }
        router.sheet { ProbeBuilder.build() }
        await waitForRouterOperations(count: 2)
        let child = try #require(base.sheetDestination)
        Router(child).dismissToRoot()
        await waitForRouterOperations()
        #expect(base.sheetDestination == nil)
        #expect(base.path.count == 1)
    }

    @Test("resetToRoot closes every presentation and clears the pushes")
    func resetToRoot() async throws {
        let (router, base) = makeRouter()
        router.push { ProbeBuilder.build() }
        router.sheet { ProbeBuilder.build() }
        await waitForRouterOperations(count: 2)
        let child = try #require(base.sheetDestination)
        Router(child).resetToRoot()
        await waitForRouterOperations()
        #expect(base.sheetDestination == nil)
        #expect(base.path.isEmpty)
    }

    // MARK: - Reading the environment

    @Test("Inside a navigation stack, @Router is that stack's router")
    func readsTheStacksRouter() async {
        let recorder = Recorder()
        let base = _Router { ProbeScreen(recorder: recorder) }
        await render(ViewNavigationWrapper(router: base), until: recorder)
        #expect(recorder.router === base)
        #expect(recorder.navigationRouter === base)
    }

    @Test("Outside every stack, a preview's @Router is the detached router")
    func previewFallsBackToDetachedRouter() async {
        let recorder = Recorder()
        await render(PreviewProbeScreen(recorder: recorder), until: recorder)
        #expect(recorder.router === MissingRouter.detached)
    }

    // MARK: - Owning a stack

    @Test("An owned router drives its stack from outside, and views inside read the same one")
    func ownedRouter() async {
        let recorder = Recorder()
        let router = Router { ProbeScreen(recorder: recorder) }
        await render(ViewNavigationWrapper(router: router), until: recorder)
        #expect(recorder.router === router.resolved)

        router.push { ProbeBuilder.build() }
        await waitForRouterOperations()
        #expect(router.path.count == 1)
        #expect(recorder.router?.path.count == 1)
    }

    // MARK: - Helpers

    private func makeRouter() -> (Router, _Router) {
        let base = _Router { EmptyView() }
        return (Router(base), base)
    }

    /// Shows the view in a window until its body has run — SwiftUI evaluates
    /// it on a later run-loop turn, and the first render of a process can
    /// take seconds.
    private func render(_ view: some View, until recorder: Recorder) async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        for _ in 0..<1_000 where recorder.router == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        window.isHidden = true
    }
}

/// A screen's builder as an app writes it: isolated to the main actor.
@MainActor
private enum ProbeBuilder {
    static func build() -> some View {
        Text("Detail")
    }
}

/// What a probe screen's wrappers resolved to when its body ran.
@MainActor
private final class Recorder {
    var router: _Router?
    var navigationRouter: _Router?
}

/// Reads both wrappers the way a screen in the app does.
private struct ProbeScreen: View {
    let recorder: Recorder
    @Router private var router
    @NavigationWrapper private var navigation

    var body: some View {
        let _ = record()
        Text("Probe")
    }

    private func record() {
        recorder.router = router.resolved
        recorder.navigationRouter = navigation.router.resolved
    }
}

/// Reads `@Router` as a preview would. The preview flag is passed in rather
/// than set in the process environment, which SwiftUI itself reads.
private struct PreviewProbeScreen: View {
    let recorder: Recorder
    @Router private var router

    var body: some View {
        let _ = record()
        Text("Preview probe")
    }

    private func record() {
        recorder.router = router.resolved(isRunningForPreviews: true)
    }
}
