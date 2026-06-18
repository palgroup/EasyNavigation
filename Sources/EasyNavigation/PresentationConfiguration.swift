//
//  PresentationConfiguration.swift
//  EasyNavigation
//

import SwiftUI

/// Native presentation options for a `present`/`sheet` call.
///
/// These map directly to SwiftUI's presentation modifiers, giving back native
/// power that the router-driven presentation would otherwise hide:
/// - `detents` → `.presentationDetents` (half-sheet / medium / large / custom)
/// - `dragIndicatorVisibility` → `.presentationDragIndicator`
/// - `interactiveDismissDisabled` → `.interactiveDismissDisabled`
///
/// All values default to "native default" so an empty configuration is a no-op.
public struct PresentationConfiguration: Sendable {
    /// Sheet detents. Empty = native default (a full-height sheet). Ignored by `present` (full-screen cover).
    public var detents: Set<PresentationDetent>
    /// Visibility of the sheet's drag indicator.
    public var dragIndicatorVisibility: Visibility
    /// When `true`, blocks swipe-to-dismiss / interactive dismissal.
    public var interactiveDismissDisabled: Bool

    public init(
        detents: Set<PresentationDetent> = [],
        dragIndicator dragIndicatorVisibility: Visibility = .automatic,
        interactiveDismissDisabled: Bool = false
    ) {
        self.detents = detents
        self.dragIndicatorVisibility = dragIndicatorVisibility
        self.interactiveDismissDisabled = interactiveDismissDisabled
    }
}

// MARK: - Applying the configuration

extension View {
    /// Applies a `PresentationConfiguration` to a presented view. Each modifier is
    /// applied only when it differs from the native default, so an empty config is inert.
    @ViewBuilder
    func applyPresentationConfiguration(_ configuration: PresentationConfiguration) -> some View {
        self
            .applyDetents(configuration.detents)
            .presentationDragIndicator(configuration.dragIndicatorVisibility)
            .interactiveDismissDisabled(configuration.interactiveDismissDisabled)
    }

    @ViewBuilder
    private func applyDetents(_ detents: Set<PresentationDetent>) -> some View {
        if detents.isEmpty {
            self
        } else {
            self.presentationDetents(detents)
        }
    }
}
