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
            withAnimation(animation) {
                properties.views.append(
                    .init(id: viewID, view: AnyView(view))
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
        public var view: AnyView
    }
}

public class PassThroughWindow: UIWindow {
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event),
              let rootView = rootViewController?.view
        else {
            return nil
        }

        if #available(iOS 18, *) {
            for subView in rootView.subviews.reversed() {
                let pointInSubView = subView.convert(point, from: rootView)

                if subView.hitTest(pointInSubView, with: event) == subView {
                    return hitView
                }
            }

            return nil
        } else {
            return hitView == rootView ? nil : hitView
        }
    }
}
