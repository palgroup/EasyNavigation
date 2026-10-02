//
//  RouterImprovementTests.swift
//  EasyNavigationTests
//
//  Covers the fixes from the deep-dive audit: cached navigation info (R1),
//  in-place replacingPush (R2/R3), queued presentations (R4), direct
//  dismissPresented (R5), fire-once dismiss callbacks (R6), per-screen native
//  bar opt-in (N1), presentation configuration (N3), and ViewDestination routing (C1).
//

import Testing
import SwiftUI
@testable import EasyNavigation

private enum TestRoute: ViewDestination {
    case profile
    case settings

    var body: some View {
        switch self {
        case .profile: Text("Profile")
        case .settings: Text("Settings")
        }
    }
}

@MainActor
@Suite("Router Improvements")
struct RouterImprovementTests {

    // MARK: - R1: cached navigation information

    @Test("navigationInformation returns a stable cached instance")
    func navInfoCached() {
        let router = _Router { EmptyView() }
        let root1 = router.navigationInformation(isPushed: false)
        let root2 = router.navigationInformation(isPushed: false)
        let pushed1 = router.navigationInformation(isPushed: true)
        let pushed2 = router.navigationInformation(isPushed: true)

        #expect(root1 === root2)        // same identity across renders → no env churn
        #expect(pushed1 === pushed2)
        #expect(root1 !== pushed1)
        #expect(root1.navigationType == .root)
        #expect(root1.isPushed == false)
        #expect(pushed1.isPushed == true)
    }

    // MARK: - R2/R3: replacingPush replaces the correct identity in place

    @Test("replacingPush replaces only the top element's identity")
    func replacingPushIdentity() async {
        let router = _Router { EmptyView() }
        router.push { Text("A") }
        router.push { Text("B") }
        router.push { Text("C") }
        await waitForRouterOperations(count: 3)
        let idA = router.path[0].id
        let idB = router.path[1].id
        let idC = router.path[2].id

        router.replacingPush { Text("D") }
        await waitForRouterOperations()

        #expect(router.path.count == 3)
        #expect(router.path[0].id == idA)   // lower stack untouched
        #expect(router.path[1].id == idB)
        #expect(router.path[2].id != idC)   // top swapped for a new identity
    }

    // MARK: - N1: per-screen native bar opt-in flag

    @Test("push carries the showsNavigationBar flag")
    func pushShowsNavBarFlag() async {
        let router = _Router { EmptyView() }
        router.push(showsNavigationBar: true) { Text("A") }
        await waitForRouterOperations()
        #expect(router.path.last?.showsNavigationBar == true)

        router.push { Text("B") } // default
        await waitForRouterOperations()
        #expect(router.path.last?.showsNavigationBar == false)
    }

    @Test("root showsNavigationBar defaults to false and is configurable")
    func rootShowsNavBar() {
        #expect(_Router { EmptyView() }.showsNavigationBar == false)
        #expect(_Router(showsNavigationBar: true) { EmptyView() }.showsNavigationBar == true)
    }

    // MARK: - N3: presentation configuration stored on the presented child

    @Test("present stores presentation configuration on the child")
    func presentStoresConfiguration() async {
        let router = _Router { EmptyView() }
        let config = PresentationConfiguration(detents: [.medium], interactiveDismissDisabled: true)
        router.present(configuration: config) { Text("Sheet") }
        await waitForRouterOperations()
        #expect(router.fullScreenDestination?.presentationConfiguration.interactiveDismissDisabled == true)
        #expect(router.fullScreenDestination?.presentationConfiguration.detents == [.medium])
    }

    // MARK: - R6: dismiss callbacks fire exactly once

    @Test("fireFullScreenDismiss is idempotent")
    func fireDismissOnce() async {
        let router = _Router { EmptyView() }
        var count = 0
        router.present({ Text("Modal") }, onDismiss: { count += 1 })
        await waitForRouterOperations()

        router.fireFullScreenDismiss()
        router.fireFullScreenDismiss()
        #expect(count == 1)
    }

    @Test("deep link replacement fires the displaced sheet's onDismiss")
    func deepLinkFiresOldDismiss() async {
        let center = DeepLinkCenter()
        center.register { (url: URL) -> Text? in Text("Deep") }
        let router = _Router { EmptyView() }
        center.setRootRouter(Router(router))

        var dismissed = false
        router.sheet({ Text("Existing") }, onDismiss: { dismissed = true })
        await waitForRouterOperations()
        #expect(router.sheetDestination != nil)

        center.handle(URL(string: "myapp://deep")!)
        #expect(dismissed == true)            // old callback fired, not dropped
        #expect(router.sheetDestination != nil) // replaced with the deep-link sheet
    }

    // MARK: - R4: a presentation requested while busy is queued, then drained

    @Test("second presentation is queued and drained after dismiss")
    func pendingPresentationDrains() async {
        let router = _Router { EmptyView() }
        router.present { Text("First") }
        await waitForRouterOperations()
        let firstChild = router.fullScreenDestination
        #expect(firstChild != nil)

        // Requested while busy → must NOT replace First; it is queued.
        router.present { Text("Second") }
        await waitForRouterOperations()
        #expect(router.fullScreenDestination === firstChild)

        // Dismiss First, then drain (the view layer does this in onDismiss).
        firstChild?.dismiss()
        await waitForRouterOperations()
        #expect(router.fullScreenDestination == nil)

        router.drainPendingPresentation()
        await waitForRouterOperations()
        #expect(router.fullScreenDestination != nil)         // Second now presented
        #expect(router.fullScreenDestination !== firstChild)
    }

    // MARK: - R5: dismissPresented clears the router's own destination directly

    @Test("dismissPresented clears the router's own presentation")
    func dismissPresentedClearsOwn() async {
        let router = _Router { EmptyView() }
        router.sheet { Text("Sheet") }
        await waitForRouterOperations()
        #expect(router.sheetDestination != nil)

        router.dismissPresented()
        await waitForRouterOperations()
        #expect(router.sheetDestination == nil)
        #expect(router.isPresenting == false)
    }

    // MARK: - C1: ViewDestination (enum) routing without nonisolated(unsafe)

    @Test("ViewDestination push and present work")
    func viewDestinationRouting() async {
        let router = _Router { EmptyView() }
        router.push(TestRoute.profile)
        await waitForRouterOperations()
        #expect(router.path.count == 1)

        router.present(TestRoute.settings)
        await waitForRouterOperations()
        #expect(router.fullScreenDestination != nil)
    }

    // MARK: - dismissToRoot from a nested child (single-operation rewrite)

    @Test("dismissToRoot from a nested child clears all presentations")
    func dismissToRootFromNested() async {
        let root = _Router { EmptyView() }
        root.present { Text("L1") }
        await waitForRouterOperations()
        guard let l1 = root.fullScreenDestination else { Issue.record("no L1"); return }
        l1.present { Text("L2") }
        await waitForRouterOperations()
        guard let l2 = l1.fullScreenDestination else { Issue.record("no L2"); return }

        l2.dismissToRoot()
        await waitForRouterOperations()
        #expect(root.fullScreenDestination == nil)
    }
}
