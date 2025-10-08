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

public struct ViewNavigationWrapper: View {
    @Environment(RouterStack.self) private var routerStack
    
    @State var router: Router
    
    public init<Content: View>(parent: Router? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.router = Router(parent: parent, root: content)
    }
    
    public var body: some View {
        NavigationStack(path: $router.path) {
            router.root()
                .id(router.rootViewID)
                .environment(createNavigationInformation(isPushed: false))
                .navigationDestination(for: DestinationWrapper.self) { wrapper in
                    wrapper
                        .destination
                        .id(wrapper.id)
                        .toolbar(.hidden, for: .navigationBar)
                        .environment(router)
                        .environment(
                            createNavigationInformation(
                                isPushed: !wrapper.isTransitioningToRoot
                            )
                        )
                }
                .environment(router)
                .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $router.fullScreenDestination, onDismiss: {
            router.operateDismiss()
        }) { wrapper in
            ViewNavigationWrapper(parent: router) {
                wrapper.destination
            }
            .environment(createNavigationInformation(isPushed: false))
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $router.sheetDestination, onDismiss: {
            router.operateDismiss()
        }) { wrapper in
            ViewNavigationWrapper(parent: router) {
                wrapper.destination
            }
            .environment(createNavigationInformation(isPushed: false))
            .toolbar(.hidden, for: .navigationBar)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            routerStack.push(router)
        }
        .onDisappear {
            router.fullScreenDestination = nil
            router.sheetDestination = nil
            routerStack.pop(router)
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
