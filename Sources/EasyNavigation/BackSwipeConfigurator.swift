//
//  BackSwipeConfigurator.swift
//  EasyNavigation
//
//  Created by EasyNavigation on 2026-03-15.
//

import SwiftUI

/// Scoped back swipe control for EasyNavigation's NavigationStack only.
/// Finds the hosting UINavigationController and configures its
/// interactive pop gesture based on the per-view allowsBackSwipe flag.
/// Does NOT affect other UINavigationControllers in the app (CometChat, etc.).
struct BackSwipeConfigurator: UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeUIViewController(context: Context) -> BackSwipeProxyController {
        let controller = BackSwipeProxyController()
        controller.isSwipeEnabled = isEnabled
        return controller
    }

    func updateUIViewController(_ uiViewController: BackSwipeProxyController, context: Context) {
        uiViewController.isSwipeEnabled = isEnabled
        uiViewController.updateGesture()
    }
}

final class BackSwipeProxyController: UIViewController, UIGestureRecognizerDelegate {
    var isSwipeEnabled: Bool = true

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        updateGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateGesture()
    }

    func updateGesture() {
        guard let nav = findNavigationController() else { return }
        nav.interactivePopGestureRecognizer?.delegate = self
        nav.interactivePopGestureRecognizer?.isEnabled = isSwipeEnabled
    }

    private func findNavigationController() -> UINavigationController? {
        var current: UIViewController? = self
        while let vc = current {
            if let nav = vc as? UINavigationController {
                return nav
            }
            current = vc.parent
        }
        return nil
    }

    // MARK: - UIGestureRecognizerDelegate
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = findNavigationController() else { return false }
        return nav.viewControllers.count > 1 && isSwipeEnabled
    }
}
