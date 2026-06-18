//
//  SplitNavigationWrapper.swift
//  EasyNavigation
//
//  Adaptive two-column navigation via native `NavigationSplitView` (iPad/Mac get a
//  sidebar+detail layout; compact widths collapse to a stack automatically).
//  The detail column can host a `ViewNavigationWrapper` or `TypedNavigationWrapper`
//  to get push navigation within the detail pane.
//

import SwiftUI

@MainActor
public struct SplitNavigationWrapper<Sidebar: View, Detail: View>: View {
    @State private var columnVisibility: NavigationSplitViewVisibility
    private let sidebar: () -> Sidebar
    private let detail: () -> Detail

    public init(
        columnVisibility: NavigationSplitViewVisibility = .automatic,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self._columnVisibility = State(initialValue: columnVisibility)
        self.sidebar = sidebar
        self.detail = detail
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar()
        } detail: {
            detail()
        }
    }
}
