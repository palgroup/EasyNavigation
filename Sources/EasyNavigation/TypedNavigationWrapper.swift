//
//  TypedNavigationWrapper.swift
//  EasyNavigation
//
//  A native, value-based navigation container backed by `TypedRouter<Route>`.
//  This is the type-safe counterpart to `ViewNavigationWrapper`: it uses SwiftUI's
//  own `navigationDestination(for:)` and a `[Route]` path, so native value-based
//  links, deep-linking and state restoration all work.
//

import SwiftUI

@MainActor
public struct TypedNavigationWrapper<Route: Hashable, Root: View, Destination: View>: View {
    @State private var router: TypedRouter<Route>
    private let root: () -> Root
    private let destination: (Route) -> Destination

    /// - Parameters:
    ///   - router: the value-based router (inject your own for restoration, or let it default).
    ///   - root: the root screen.
    ///   - destination: maps a pushed `Route` value to its view.
    public init(
        router: TypedRouter<Route> = TypedRouter(),
        @ViewBuilder root: @escaping () -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self._router = State(initialValue: router)
        self.root = root
        self.destination = destination
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            root()
                .environment(router)
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .environment(router)
                }
        }
    }
}
