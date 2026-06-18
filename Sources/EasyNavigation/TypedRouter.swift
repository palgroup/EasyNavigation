//
//  TypedRouter.swift
//  EasyNavigation
//
//  Value-based navigation: drives a native NavigationStack with the consumer's own
//  `Hashable` route type. Unlike the closure-based `Router`, the stack is a plain
//  `[Route]` array — which means value-based deep-linking (set the whole path from
//  data) and, when `Route: Codable`, scene/state restoration after process death.
//

import SwiftUI

@MainActor
@Observable
public final class TypedRouter<Route: Hashable> {
    /// The navigation stack as the consumer's own route values. Bound directly to a
    /// native `NavigationStack(path:)`, so SwiftUI and this router share one source of truth.
    public var path: [Route]

    public init(path: [Route] = []) {
        self.path = path
    }

    /// Number of pushed routes (root not included).
    public var depth: Int { path.count }

    // MARK: - Navigation

    public func push(_ route: Route) {
        path.append(route)
    }

    public func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    public func popToRoot() {
        path.removeAll()
    }

    /// Pops back to the last occurrence of `route`, keeping it on the stack.
    /// No-op if the route isn't present.
    public func pop(to route: Route) {
        guard let index = path.lastIndex(of: route) else { return }
        path.removeSubrange((index + 1)..<path.count)
    }

    /// Replaces the entire stack — value-based deep-linking: jump several screens deep
    /// declaratively from data, instead of replaying individual `push` calls.
    public func setPath(_ newPath: [Route]) {
        path = newPath
    }
}

// MARK: - State restoration (Codable routes)

extension TypedRouter where Route: Codable {
    /// Encodes the current stack for persistence (e.g. `@SceneStorage`).
    public func encodedPath() throws -> Data {
        try JSONEncoder().encode(path)
    }

    /// Restores a stack previously produced by `encodedPath()`.
    public func restore(from data: Data) throws {
        path = try JSONDecoder().decode([Route].self, from: data)
    }
}
