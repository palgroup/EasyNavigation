//
//  ViewNavigationWrapper.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import SwiftUI

@MainActor
public struct ViewNavigationWrapper: View {
    @State var router: Router

    public init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        self._router = State(initialValue: Router(root: content))
    }

    public init(router: Router) {
        self._router = State(initialValue: router)
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            router.rootView
                .environment(router)
                .environment(createNavigationInformation(isPushed: false))
                .navigationDestination(for: DestinationWrapper.self) { wrapper in
                    wrapper.contentView
                        .background(BackSwipeConfigurator(isEnabled: wrapper.allowsBackSwipe))
                        .toolbar(.hidden, for: .navigationBar)
                        .environment(router)
                        .environment(
                            createNavigationInformation(
                                isPushed: true
                            )
                        )
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $router.fullScreenDestination, onDismiss: { [weak router] in
            router?.onFullScreenDismiss?()
            router?.onFullScreenDismiss = nil
        }) { wrapper in
            ViewNavigationWrapper(router: wrapper)
        }
        .sheet(item: $router.sheetDestination, onDismiss: { [weak router] in
            router?.onSheetDismiss?()
            router?.onSheetDismiss = nil
        }) { wrapper in
            ViewNavigationWrapper(router: wrapper)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            NavigationLogger.debug("ViewNavigationWrapper appeared - hasParent=\(router.parent != nil)")
        }
        .onDisappear {
            NavigationLogger.debug("ViewNavigationWrapper disappeared - hasParent=\(router.parent != nil)")
        }
    }

    private func createNavigationInformation(isPushed: Bool) -> NavigationInformations {
        return NavigationInformations(
            isPushed: isPushed,
            isPresenting: router.parent != nil,
            navigationType: router.parent == nil ? .root : router.parent?.fullScreenDestination != nil ? .present : .sheet
        )
    }
}
