//
//  RouterTests.swift
//  EasyNavigationTests
//

import Testing
import SwiftUI
@testable import EasyNavigation

@MainActor
@Suite("Router Core Navigation")
struct RouterTests {

    // MARK: - Push

    @Test("push appends to path")
    func pushAppendsToPath() async {
        let router = Router { EmptyView() }
        router.push { Text("A") }
        await waitForRouterOperations()
        #expect(router.path.count == 1)
    }

    @Test("multiple pushes maintain order")
    func multiplePushesMaintainOrder() async {
        let router = Router { EmptyView() }
        router.push { Text("A") }
        router.push { Text("B") }
        router.push { Text("C") }
        await waitForRouterOperations(count: 3)
        #expect(router.path.count == 3)
    }

    @Test("push with backSwipe disabled sets flag")
    func pushWithBackSwipeDisabled() async {
        let router = Router { EmptyView() }
        router.push(allowBackSwipe: false) { Text("A") }
        await waitForRouterOperations()
        #expect(router.path.last?.allowsBackSwipe == false)
        #expect(router.isBackSwipeAllowed == false)
    }

    @Test("push with backSwipe enabled sets flag")
    func pushWithBackSwipeEnabled() async {
        let router = Router { EmptyView() }
        router.push(allowBackSwipe: true) { Text("A") }
        await waitForRouterOperations()
        #expect(router.isBackSwipeAllowed == true)
    }

    // MARK: - Pop

    @Test("pop removes last from path")
    func popRemovesLast() async {
        let router = Router { EmptyView() }
        router.push { Text("A") }
        router.push { Text("B") }
        await waitForRouterOperations(count: 2)

        router.pop()
        await waitForRouterOperations()
        #expect(router.path.count == 1)
    }

    @Test("pop on empty path does not crash")
    func popEmptyPathNoCrash() async {
        let router = Router { EmptyView() }
        router.pop()
        await waitForRouterOperations()
        #expect(router.path.count == 0)
    }

    @Test("popToRoot clears entire path")
    func popToRootClearsPath() async {
        let router = Router { EmptyView() }
        router.push { Text("A") }
        router.push { Text("B") }
        router.push { Text("C") }
        await waitForRouterOperations(count: 3)

        router.popToRoot()
        await waitForRouterOperations()
        #expect(router.path.isEmpty)
    }

    // MARK: - isBackSwipeAllowed

    @Test("isBackSwipeAllowed returns true when path is empty")
    func backSwipeAllowedOnEmptyPath() {
        let router = Router { EmptyView() }
        #expect(router.isBackSwipeAllowed == true)
    }
}
