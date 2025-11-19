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
//    private(set) public var routerStack: RouterStack
//    private(set) public var deeplinkCenter: DeepLinkCenter

    // Root view management
    public var rootView: AnyView = AnyView(EmptyView())
    public var rootViewID = UUID()

    private weak var windowScene: UIWindowScene?

    public init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
//        let routerStack = RouterStack()
//        deeplinkCenter = DeepLinkCenter(routerStack: routerStack)
//        self.routerStack = routerStack
        self.rootView = AnyView(content())
        self.rootViewID = UUID()
    }

    /// Set new root view with proper cleanup to prevent memory leaks
    /// Uses a 4-phase approach to ensure all routers (including those in TabView) are properly deallocated
    public func setRoot<V: View>(@ViewBuilder content: @escaping () -> V) {
        print("🔄 [GlobalRouter] Setting new root - Phase 0: Cleanup routers BEFORE destroying view")

        // Phase 0: Cleanup all routers FIRST (while views are still alive)
        // This is critical - we must cleanup BEFORE SwiftUI destroys the views
//        routerStack.cleanupAllRouters()

        print("🔄 [GlobalRouter] Phase 1: Clearing old view with EmptyView")

        // Phase 1: Now replace with EmptyView to destroy the view hierarchy
        // At this point routers are already cleaned up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.rootView = AnyView(EmptyView())
            self.rootViewID = UUID()
        }

        // Phase 2: Remove router references from stack
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            print("🔄 [GlobalRouter] Phase 2: Remove router references")
//            self.routerStack.removeAllPendings()
        }

        // Phase 3: Set new root view after sufficient delay for SwiftUI teardown
        // Increased delay to 1.0s to allow SwiftUI to complete @State cleanup
        // This is critical for TabView scenarios where multiple @State routers exist
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            print("🔄 [GlobalRouter] Phase 3: Setting new view")
            self.rootView = AnyView(content())
            self.rootViewID = UUID()
            print("✅ [GlobalRouter] Root set complete, new ID: \(self.rootViewID)")
        }
    }

    public func setup(scene: UIWindowScene) {
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
