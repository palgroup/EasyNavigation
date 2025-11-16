//
//  ViewNavigationWrapper.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import SwiftUI

struct SwipeConfiguration {
    @MainActor static var backSwipeAvailable: Bool = false
    
}
// MARK: - UINavigationController Extension for Back Swipe Gesture
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1 && SwipeConfiguration.backSwipeAvailable
    }
}


@MainActor
public struct ViewNavigationWrapper: View {
    @State var router: Router
    
    public init<Content: View>(routerStack: RouterStack, @ViewBuilder content: @escaping () -> Content) {
        self._router = State(wrappedValue: Router(routerStack: routerStack, root: content))
    }
    
    public init(router: Router) {
        self._router = State(wrappedValue: router)
    }
    
    public var body: some View {
        NavigationStack(path: $router.path) {
            router.root()
                .id(router.rootViewID)
                .environment(router)
                .environment(createNavigationInformation(isPushed: false))
                .navigationDestination(for: DestinationWrapper.self) { wrapper in
                    wrapper.destination
                        .id(wrapper.id)
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
        .fullScreenCover(item: $router.fullScreenDestination, onDismiss: {
            router.onFullScreenDismiss?()
            router.onFullScreenDismiss = nil
        }) { wrapper in
            ViewNavigationWrapper(router: wrapper)
        }
        .sheet(item: $router.sheetDestination, onDismiss: {
            router.onSheetDismiss?()
            router.onSheetDismiss = nil
        }) { wrapper in
            ViewNavigationWrapper(router: wrapper)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let routerId = ObjectIdentifier(router)
            let hasParent = router.parent != nil
            print("📱 [ViewNavigationWrapper] Router2(\(routerId)) appeared, hasParent=\(hasParent)")
        }
        .onDisappear {
            let routerId = ObjectIdentifier(router)
            let hasParent = router.parent != nil
            print("👋 [ViewNavigationWrapper] Router2(\(routerId)) disappeared, hasParent=\(hasParent)")
        }
        .id(router.id)
    }
    
    private func createNavigationInformation(isPushed: Bool) -> NavigationInformations {
        return NavigationInformations(
            isPushed: isPushed,
            isPresenting: router.parent != nil,
            navigationType: router.parent == nil ? .root : router.parent?.fullScreenDestination != nil ? .present : .sheet
        )
    }
}
