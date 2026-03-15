//
//  AppRoot.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 16.11.2025.
//

import SwiftUI

public struct AppRoot<C: View>: View {
    @State private var globalRouter = GlobalRouter()
    private var content: C

    public init(@ViewBuilder content: @escaping () -> C) {
        self.content = content()
    }

    public var body: some View {
        content
            .environment(globalRouter)
            .environment(globalRouter.overlayProperties)
            .task {
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                    return
                }
                globalRouter.setup(scene: scene)
            }
    }
}
