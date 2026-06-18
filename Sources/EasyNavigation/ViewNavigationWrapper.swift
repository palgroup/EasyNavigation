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

    public init<Content: View>(showsNavigationBar: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self._router = State(initialValue: Router(showsNavigationBar: showsNavigationBar, root: content))
    }

    public init(router: Router) {
        self._router = State(initialValue: router)
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            router.rootView
                .environment(router)
                .environment(router.navigationInformation(isPushed: false))
                .navigationDestination(for: DestinationWrapper.self) { wrapper in
                    wrapper.contentView
                        .background(BackSwipeConfigurator(isEnabled: wrapper.allowsBackSwipe))
                        // Native bar is opt-in per screen: hidden by default (custom-header
                        // behavior), `.automatic` when the screen asked for the native bar so
                        // its own .navigationTitle/.toolbar/back button work.
                        .toolbar(wrapper.showsNavigationBar ? .automatic : .hidden, for: .navigationBar)
                        .environment(router)
                        .environment(router.navigationInformation(isPushed: true))
                }
                .toolbar(router.showsNavigationBar ? .automatic : .hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $router.fullScreenDestination, onDismiss: {
            // Fire-once dismiss callback, then drain any presentation queued while busy.
            router.fireFullScreenDismiss()
            router.drainPendingPresentation()
        }) { wrapper in
            ViewNavigationWrapper(router: wrapper)
                .applyPresentationConfiguration(wrapper.presentationConfiguration)
        }
        .sheet(item: $router.sheetDestination, onDismiss: {
            router.fireSheetDismiss()
            router.drainPendingPresentation()
        }) { wrapper in
            ViewNavigationWrapper(router: wrapper)
                .applyPresentationConfiguration(wrapper.presentationConfiguration)
        }
        .onAppear {
            NavigationLogger.debug("ViewNavigationWrapper appeared - hasParent=\(router.parent != nil)")
        }
        .onDisappear {
            NavigationLogger.debug("ViewNavigationWrapper disappeared - hasParent=\(router.parent != nil)")
        }
    }
}
