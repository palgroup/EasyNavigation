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
//    @Environment(RouterStack.self) var stack
    
    public init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        self._router = State(initialValue: Router(root: content))
    }
    
    public init(router: Router) {
        self._router = State(initialValue: router)
    }
    
    public var body: some View {
        NavigationStack(path: $router.path) {
            router.root
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
            let routerId = ObjectIdentifier(router)
            let hasParent = router.parent != nil
            print("📱 [ViewNavigationWrapper] Router2(\(routerId)) appeared, hasParent=\(hasParent)")
//            stack.push(router)
        }
        .onDisappear {
            let routerId = ObjectIdentifier(router)
            let hasParent = router.parent != nil
            print("👋 [ViewNavigationWrapper] Router2(\(routerId)) disappeared, hasParent=\(hasParent)")
//            stack.pop(router)
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
