//
//  ViewDestinationRepresentable.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import Foundation
import SwiftUI

@available(*, deprecated, message: "Use ViewDestination instead for type-safe routing")
public protocol ViewDestinationRepresentable: Sendable {
    var view: AnyView { get }
}

/// Modern destination protocol for enum-based routing.
/// Provides type-safe view construction without AnyView.
///
/// Usage:
/// ```swift
/// enum AppRoute: ViewDestination {
///     case profile(id: String)
///     case settings
///
///     var body: some View {
///         switch self {
///         case .profile(let id): ProfileView(userId: id)
///         case .settings: SettingsView()
///         }
///     }
/// }
///
/// router.push(AppRoute.profile(id: "123"))
/// ```
public protocol ViewDestination: Sendable, Hashable {
    associatedtype Body: View
    @MainActor @ViewBuilder var body: Body { get }
}
