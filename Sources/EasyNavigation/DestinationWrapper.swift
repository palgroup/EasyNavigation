//
//  DestinationWrapper.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import Foundation
import SwiftUI

public struct DestinationWrapper: Identifiable, Hashable {
    public let id = UUID()
    let allowsBackSwipe: Bool

    /// Deferred view construction — only evaluated when SwiftUI renders
    private let _makeContent: @MainActor @Sendable () -> AnyView

    init<Content: View>(
        allowsBackSwipe: Bool = true,
        @ViewBuilder content: @escaping @MainActor @Sendable () -> Content
    ) {
        self.allowsBackSwipe = allowsBackSwipe
        self._makeContent = { AnyView(content()) }
    }

    /// Concrete view for rendering — gives SwiftUI stable structural identity
    var contentView: DestinationContentView {
        DestinationContentView(render: _makeContent)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

/// Concrete View type for SwiftUI structural identity at the navigation destination level.
/// SwiftUI sees this as a stable type rather than AnyView, enabling better diffing.
struct DestinationContentView: View {
    let render: @MainActor @Sendable () -> AnyView

    var body: some View {
        render()
    }
}
