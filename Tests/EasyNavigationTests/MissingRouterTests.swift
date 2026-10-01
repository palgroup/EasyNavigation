//
//  MissingRouterTests.swift
//  EasyNavigationTests
//

import Testing
import SwiftUI
@testable import EasyNavigation

@Suite("Missing router")
@MainActor
struct MissingRouterTests {

    @Test("A preview gets the detached router")
    func previewGetsDetachedRouter() {
        let substitute = MissingRouter.substitute(isRunningForPreviews: true)
        #expect(substitute === MissingRouter.detached)
    }

    @Test("The app gets no substitute, so the wrapper stops")
    func appGetsNoSubstitute() {
        #expect(MissingRouter.substitute(isRunningForPreviews: false) == nil)
    }

    @Test("A router in the environment is always used as-is")
    func environmentRouterWins() {
        let router = Router { EmptyView() }
        #expect(MissingRouter.resolve(router, in: "Test") === router)
    }

    @Test("The detached router is a root with an empty path")
    func detachedRouterIsEmpty() {
        #expect(MissingRouter.detached.path.isEmpty)
        #expect(MissingRouter.detached.isPresenting == false)
    }
}
