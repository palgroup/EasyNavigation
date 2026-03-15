//
//  RouterEdgeCaseTests.swift
//  EasyNavigationTests
//

import Testing
import SwiftUI
@testable import EasyNavigation

@MainActor
@Suite("Router Edge Cases")
struct RouterEdgeCaseTests {

    @Test("replacingPush on empty path replaces root")
    func replacingPushEmptyPath() async {
        let router = Router { Text("Original") }
        let originalRootID = router.rootViewID
        router.replacingPush { Text("Replaced") }
        await waitForRouterOperations()
        #expect(router.rootViewID != originalRootID)
        #expect(router.path.isEmpty)
    }

    @Test("replacingPush on single element path does not crash")
    func replacingPushSingleElement() async {
        let router = Router { EmptyView() }
        router.push { Text("A") }
        await waitForRouterOperations()
        #expect(router.path.count == 1)

        router.replacingPush { Text("B") }
        await waitForRouterOperations()
        // A replaced by B → still 1 element
        #expect(router.path.count == 1)
    }

    @Test("replacingPush on multiple elements replaces top only")
    func replacingPushMultipleElements() async {
        let router = Router { EmptyView() }
        router.push { Text("A") }
        await waitForRouterOperations()
        router.push { Text("B") }
        await waitForRouterOperations()
        router.push { Text("C") }
        await waitForRouterOperations()
        #expect(router.path.count == 3)

        router.replacingPush { Text("D") }
        await waitForRouterOperations()
        // [A, B, C] → push D → [A, B, C, D] → remove C → [A, B, D]
        #expect(router.path.count == 3)
    }

    @Test("cleanup breaks retain cycles")
    func cleanupBreaksRetainCycles() async {
        let router = Router { EmptyView() }
        router.present { Text("Modal") }
        await waitForRouterOperations()
        #expect(router.fullScreenDestination != nil)

        router.cleanup()
        #expect(router.fullScreenDestination == nil)
        #expect(router.sheetDestination == nil)
        #expect(router.path.isEmpty)
    }

    @Test("cleanup cancels processing task")
    func cleanupCancelsProcessing() async {
        let router = Router { EmptyView() }
        router.cleanup()
        // Push after cleanup — should be no-op since continuation is finished
        router.push { Text("A") }
        await waitForRouterOperations()
        #expect(router.path.isEmpty)
    }

    @Test("rapid push does not corrupt path")
    func rapidPush() async {
        let router = Router { EmptyView() }
        for i in 0..<20 {
            router.push { Text("View \(i)") }
        }
        await waitForRouterOperations(count: 20)
        #expect(router.path.count == 20)
    }

    @Test("rapid pop does not corrupt path")
    func rapidPop() async {
        let router = Router { EmptyView() }
        for i in 0..<10 {
            router.push { Text("View \(i)") }
        }
        await waitForRouterOperations(count: 10)
        #expect(router.path.count == 10)

        for _ in 0..<10 {
            router.pop()
        }
        await waitForRouterOperations(count: 10)
        #expect(router.path.isEmpty)
    }

    @Test("present while already presenting sheet is blocked")
    func presentWhilePresentingSheetBlocked() async {
        let router = Router { EmptyView() }
        router.sheet { Text("Sheet") }
        await waitForRouterOperations()
        #expect(router.sheetDestination != nil)

        router.present { Text("FullScreen") }
        await waitForRouterOperations()
        // Should still only have sheet, fullscreen should be blocked
        #expect(router.sheetDestination != nil)
        #expect(router.fullScreenDestination == nil)
    }

    @Test("dismissToRoot clears all presentations")
    func dismissToRootClearsAll() async {
        let router = Router { EmptyView() }
        router.present { Text("Level 1") }
        await waitForRouterOperations()

        guard let child = router.fullScreenDestination else {
            Issue.record("fullScreenDestination should not be nil")
            return
        }
        child.present { Text("Level 2") }
        await waitForRouterOperations()
        #expect(child.fullScreenDestination != nil)

        router.dismissToRoot()
        await waitForRouterOperations()
        #expect(router.fullScreenDestination == nil)
        #expect(router.sheetDestination == nil)
    }
}
