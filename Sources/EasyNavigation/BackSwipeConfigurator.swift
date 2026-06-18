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

    /// SwiftUI's original pop-gesture delegate, preserved so we can restore it on
    /// teardown instead of leaving the shared navigation controller's `weak` delegate
    /// dangling (which would fall back to nil and break the gesture).
    private weak var originalGestureDelegate: UIGestureRecognizerDelegate?
    private weak var configuredNavigationController: UINavigationController?

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        updateGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateGesture()
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        // When removed, hand the gesture's delegate back to SwiftUI rather than
        // leaving it pointed at a controller that's going away.
        if parent == nil,
           let gesture = configuredNavigationController?.interactivePopGestureRecognizer,
           gesture.delegate === self {
            gesture.delegate = originalGestureDelegate
        }
    }

    func updateGesture() {
        guard let nav = findNavigationController(),
              let gesture = nav.interactivePopGestureRecognizer else { return }
        configuredNavigationController = nav
        // Capture SwiftUI's delegate once, then install ourselves so the back-swipe
        // keeps working even with the navigation bar hidden (the library's intent).
        if gesture.delegate !== self {
            originalGestureDelegate = gesture.delegate
            gesture.delegate = self
        }
        gesture.isEnabled = isSwipeEnabled
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
