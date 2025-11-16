//
//  WindowRoot.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 20.10.2025.
//

import SwiftUI

public struct WindowRoot<C: View>: View {
    let content: C
    @State var properties = UniversalOverlayProperties()
    @State var routerStack: RouterStack = RouterStack()
    @State var deeplinkCenter: DeepLinkCenter

    public init(@ViewBuilder content: @escaping () -> C) {
        self.content = content()
        let stack = RouterStack()
        _routerStack = State(initialValue: stack)
        self._deeplinkCenter = State(initialValue: DeepLinkCenter(routerStack: stack))
    }

    public var body: some View {
        ViewNavigationWrapper(routerStack: routerStack) {
            content
        }
        .environment(properties)
        .environment(routerStack)
        .environmentObject(deeplinkCenter)
        .onAppear {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let window = PassThroughWindow(windowScene: windowScene)
                window.isHidden = false
                window.isUserInteractionEnabled = true

                let rootViewController = UIHostingController(
                    rootView: UniversalOverlayViews()
                        .environment(properties)
                )
                rootViewController.view.backgroundColor = .clear
                window.rootViewController = rootViewController
                properties.window = window
            }
        }
    }
}

fileprivate struct UniversalOverlayViews: View {
    @Environment(UniversalOverlayProperties.self) private var properties

    var body: some View {
        ZStack {
            ForEach(properties.views, id: \.id) {
                $0.view
            }
        }
    }
}
