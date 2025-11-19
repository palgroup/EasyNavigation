//
//  AppRoot.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 16.11.2025.
//

import SwiftUI

public struct AppRoot<C: View>: View {
    @State private var globalRouter: GlobalRouter
    
    public init(@ViewBuilder content: @escaping () -> C) {
        self._globalRouter = State(initialValue: GlobalRouter(content: content))
    }
    
    public var body: some View {
        globalRouter.rootView
//            .environment(globalRouter.routerStack)
//            .environmentObject(globalRouter.deeplinkCenter)
            .environment(globalRouter)
            .environment(globalRouter.overlayProperties)
            .id(globalRouter.rootViewID)
            .task {
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                    return
                }
                globalRouter.setup(scene: scene)
            }
    }
}
