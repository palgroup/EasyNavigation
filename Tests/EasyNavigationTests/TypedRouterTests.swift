//
//  TypedRouterTests.swift
//  EasyNavigationTests
//
//  Covers value-based navigation + Codable state restoration (audit finding N4).
//

import Testing
import SwiftUI
@testable import EasyNavigation

private enum AppRoute: Hashable, Codable {
    case home
    case profile(String)
    case settings
}

@MainActor
@Suite("TypedRouter")
struct TypedRouterTests {

    @Test("push and pop maintain the value stack")
    func pushPop() {
        let router = TypedRouter<AppRoute>()
        router.push(.home)
        router.push(.profile("1"))
        #expect(router.path == [.home, .profile("1")])

        router.pop()
        #expect(router.path == [.home])

        router.pop()
        router.pop() // safe on empty
        #expect(router.path.isEmpty)
    }

    @Test("setPath enables value-based deep-linking")
    func setPath() {
        let router = TypedRouter<AppRoute>()
        router.setPath([.home, .settings, .profile("42")])
        #expect(router.depth == 3)
        #expect(router.path.last == .profile("42"))
    }

    @Test("pop(to:) trims everything above the target, keeping it")
    func popTo() {
        let router = TypedRouter<AppRoute>(path: [.home, .settings, .profile("1")])
        router.pop(to: .settings)
        #expect(router.path == [.home, .settings])
    }

    @Test("pop(to:) on the top element is a no-op")
    func popToTop() {
        let router = TypedRouter<AppRoute>(path: [.home, .settings])
        router.pop(to: .settings)
        #expect(router.path == [.home, .settings])
    }

    @Test("pop(to:) on a missing route is a no-op")
    func popToMissing() {
        let router = TypedRouter<AppRoute>(path: [.home, .settings])
        router.pop(to: .profile("nope"))
        #expect(router.path == [.home, .settings])
    }

    @Test("popToRoot clears the stack")
    func popToRoot() {
        let router = TypedRouter<AppRoute>(path: [.home, .settings])
        router.popToRoot()
        #expect(router.path.isEmpty)
    }

    @Test("Codable path round-trips for state restoration")
    func codableRoundTrip() throws {
        let router = TypedRouter<AppRoute>(path: [.home, .profile("99"), .settings])
        let data = try router.encodedPath()

        let restored = TypedRouter<AppRoute>()
        try restored.restore(from: data)
        #expect(restored.path == [.home, .profile("99"), .settings])
    }
}
