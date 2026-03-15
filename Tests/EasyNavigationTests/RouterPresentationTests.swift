//
//  RouterPresentationTests.swift
//  EasyNavigationTests
//

import Testing
import SwiftUI
@testable import EasyNavigation

@MainActor
@Suite("Router Presentation")
struct RouterPresentationTests {

    @Test("present sets fullScreenDestination")
    func presentSetsFullScreen() async {
        let router = Router { EmptyView() }
        router.present { Text("Modal") }
        await waitForRouterOperations()
        #expect(router.fullScreenDestination != nil)
        #expect(router.isPresenting == true)
    }

    @Test("present creates child with parent reference")
    func presentCreatesChildWithParent() async {
        let router = Router { EmptyView() }
        router.present { Text("Modal") }
        await waitForRouterOperations()
        #expect(router.fullScreenDestination?.parent === router)
    }

    @Test("sheet sets sheetDestination")
    func sheetSetsDestination() async {
        let router = Router { EmptyView() }
        router.sheet { Text("Sheet") }
        await waitForRouterOperations()
        #expect(router.sheetDestination != nil)
        #expect(router.isPresenting == true)
    }

    @Test("double present is blocked")
    func doublePresentBlocked() async {
        let router = Router { EmptyView() }
        router.present { Text("First") }
        await waitForRouterOperations()

        router.present { Text("Second") }
        await waitForRouterOperations()
        // Only first should be present
        #expect(router.fullScreenDestination != nil)
        #expect(router.isPresenting == true)
    }

    @Test("dismiss clears parent fullScreen")
    func dismissClearsParentFullScreen() async {
        let router = Router { EmptyView() }
        router.present { Text("Modal") }
        await waitForRouterOperations()

        guard let child = router.fullScreenDestination else {
            Issue.record("fullScreenDestination should not be nil")
            return
        }
        child.dismiss()
        await waitForRouterOperations()
        #expect(router.fullScreenDestination == nil)
        #expect(router.isPresenting == false)
    }

    @Test("dismiss clears parent sheet")
    func dismissClearsParentSheet() async {
        let router = Router { EmptyView() }
        router.sheet { Text("Sheet") }
        await waitForRouterOperations()

        guard let child = router.sheetDestination else {
            Issue.record("sheetDestination should not be nil")
            return
        }
        child.dismiss()
        await waitForRouterOperations()
        #expect(router.sheetDestination == nil)
        #expect(router.isPresenting == false)
    }

    @Test("dismiss without parent is no-op")
    func dismissWithoutParentNoOp() async {
        let router = Router { EmptyView() }
        router.dismiss()
        await waitForRouterOperations()
        #expect(router.path.isEmpty)
    }

    @Test("isPresenting reflects state correctly")
    func isPresentingReflectsState() async {
        let router = Router { EmptyView() }
        #expect(router.isPresenting == false)

        router.present { Text("Modal") }
        await waitForRouterOperations()
        #expect(router.isPresenting == true)
    }
}
