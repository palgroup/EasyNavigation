//
//  WindowOverlay.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 20.10.2025.
//

import SwiftUI

extension View {
    @ViewBuilder
    public func windowOverlay<Content: View>(
        animation: Animation = .default,
        show: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        self.modifier(UniversalOverlayModifier(animation: animation, show: show, view: content()))
    }
}

fileprivate struct UniversalOverlayModifier<C: View>: ViewModifier {
    var animation: Animation
    @Binding var show: Bool
    @Environment(UniversalOverlayProperties.self) var properties
    var view: C

    @State private var viewID: String? = nil

    func body(content: Content) -> some View {
        content
            .onChange(of: show) { _, value in
                if value {
                    addView()
                } else {
                    removeView()
                }
            }
    }

    private func addView() {
        if properties.window != nil && viewID == nil {
            viewID = UUID().uuidString
            guard let viewID else { return }
            let capturedView = view
            withAnimation(animation) {
                properties.views.append(
                    .init(id: viewID, makeContent: { AnyView(capturedView) })
                )
            }
        }
    }

    private func removeView() {
        if let viewID {
            withAnimation(animation) {
                properties.views.removeAll { $0.id == viewID }
            }

            self.viewID = nil
        }
    }
}

@Observable
@MainActor
public final class UniversalOverlayProperties {
    public var window: UIWindow?
    public var views: [OverlayView] = []

    public init() {}

    public struct OverlayView: Identifiable {
        public var id: String = UUID().uuidString
        let makeContent: @MainActor @Sendable () -> AnyView

        /// Concrete view for rendering — gives SwiftUI stable structural identity
        var contentView: OverlayContentView {
            OverlayContentView(render: makeContent)
        }
    }
}

@MainActor
public class PassThroughWindow: UIWindow {
    public weak var overlayProperties: UniversalOverlayProperties?

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else {
            return nil
        }

        // Overlay içerik varsa, touch'ı yakala
        // SwiftUI kendi içinde doğru elemente yönlendirecek
        if let properties = overlayProperties, !properties.views.isEmpty {
            return hitView
        }

        // Overlay yoksa, pass through
        return nil
    }
}

/// Concrete View type for SwiftUI structural identity at the overlay level.
struct OverlayContentView: View {
    let render: @MainActor @Sendable () -> AnyView

    var body: some View {
        render()
    }
}
