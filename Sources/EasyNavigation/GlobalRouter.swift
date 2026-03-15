//
//  GlobalRouter.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 16.11.2025.
//

import SwiftUI

@Observable
@MainActor
public final class GlobalRouter {
    private(set) public var keyWindow: UIWindow?
    public var overlayProperties = UniversalOverlayProperties()

    private weak var windowScene: UIWindowScene?

    init() {}

    func setup(scene: UIWindowScene) {
        self.windowScene = scene

        // Mevcut key window'u yakala (uygulamanın asıl window'u)
        keyWindow = scene.windows.first { $0.isKeyWindow } ?? scene.windows.first

        // Overlay window'u oluştur
        let passThroughWindow = PassThroughWindow(windowScene: scene)
        passThroughWindow.windowLevel = .alert
        passThroughWindow.isHidden = false
        passThroughWindow.isUserInteractionEnabled = true
        passThroughWindow.overlayProperties = overlayProperties

        let rootViewController = UIHostingController(
            rootView: UniversalOverlayViews()
                .environment(overlayProperties)
        )
        rootViewController.view.backgroundColor = .clear
        passThroughWindow.rootViewController = rootViewController

        overlayProperties.window = passThroughWindow
    }

    public func show<V: View>(
        id: String = UUID().uuidString,
        @ViewBuilder content: @escaping () -> V
    ) {
        overlayProperties.views.append(
            UniversalOverlayProperties.OverlayView(id: id, view: AnyView(content()))
        )
    }

    public func dismiss(_ id: String) {
        overlayProperties.views.removeAll { $0.id == id }
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
