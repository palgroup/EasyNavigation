//
//  Router.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import SwiftUI
import Combine

@MainActor
@Observable
public class Router: Identifiable, Sendable {
    public let id = UUID().uuidString
    var root: () -> AnyView
    var path: [DestinationWrapper] = []
    var fullScreenDestination: Router?
    @ObservationIgnored
    var onFullScreenDismiss: (() -> Void)?
    var sheetDestination: Router?
    @ObservationIgnored
    var onSheetDismiss: (() -> Void)?

    var rootViewID: UUID = UUID()
    
    @ObservationIgnored
    weak var parent: Router?
    
    // Task management
    @ObservationIgnored
    private var isExecutingOperation = false
    @ObservationIgnored
    private var pendingOperations: [@MainActor () -> Void] = []
    @ObservationIgnored
    private let routerStack: RouterStack
    // Navigation timing control
    @ObservationIgnored
    public var operationDelay: Duration = .milliseconds(100)
    @ObservationIgnored
    public var waitForUIUpdate: Bool = true
    
    public var isPresenting: Bool {
        fullScreenDestination != nil || sheetDestination != nil
    }

    public init<Content: View>(
        parent: Router? = nil,
        routerStack: RouterStack,
        root: @escaping () -> Content
    ) {
        self.parent = parent
        self.root = {
            AnyView(root())
        }
        self.rootViewID = UUID()
        self.routerStack = routerStack
        self.routerStack.push(self)
    }
    
    private func executeOperation(_ operation: @escaping @MainActor () -> Void) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Add operation to queue
            pendingOperations.append(operation)
            
            // If already executing, just return - the operation will be picked up
            if isExecutingOperation {
                return
            }
            
            // Process all pending operations
            isExecutingOperation = true
            while !pendingOperations.isEmpty {
                let nextOperation = pendingOperations.removeFirst()
                nextOperation()
                
                if waitForUIUpdate {
                    await Task.yield()
                    try await Task.sleep(for: operationDelay)
                }
            }
            isExecutingOperation = false
        }
    }
    
    // MARK: - Navigation API
    public func push<Content: View>(allowBackSwipe: Bool = true, @ViewBuilder _ destination: @escaping () -> Content) {
        executeOperation { [weak self] in
            guard let self else {
                print("❌ [PUSH] Router is nil, operation cancelled")
                return
            }
            let routerId = ObjectIdentifier(self)
            print("🔵 [PUSH] Router(\(routerId)) - Current path count: \(path.count)")
            
            let wrapper = DestinationWrapper(
                destination: AnyView(destination()),
                allowsBackSwipe: allowBackSwipe
            )
            SwipeConfiguration.backSwipeAvailable = allowBackSwipe
            path.append(wrapper)
            print("✅ [PUSH] Router(\(routerId)) - Pushed. New path count: \(path.count)")
        }
    }
    
    @MainActor
    private func replaceRootWithAnimation<Content: View>(_ newRootViewGenerator: @escaping () -> Content) {
        let newRootID = UUID()
        let newGenerator = { AnyView(newRootViewGenerator()) }
        
        withAnimation(.default) {
            self.root = newGenerator
            self.rootViewID = newRootID
            self.path.removeAll()
        }
    }
    
    @MainActor
    private func replacingPushAnimated<Content: View>(_ destination: @escaping () -> Content) async {
        // Path is not empty. Replace the top view on the stack with an animation.
        let newDestinationWrapper = DestinationWrapper(destination: AnyView(destination()))
        
        // Operation 1: Append the new destination. This will be animated as a push.
        executeOperation { [weak self] in
            guard let self = self else { return }
            self.path.append(newDestinationWrapper)
        }
        
        do {
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            // Handle cancellation if necessary, e.g., by not proceeding.
            print("Task.sleep in replacingPushAnimated was cancelled: \(error)")
            return
        }
        // Operation 2: Remove the item that was previously at the top (now second to last).
        // Do this without animation.
        // The existing executeOperation mechanism provides a small delay (operationDelay)
        // between Op1 and Op2 here.
        executeOperation { [weak self] in
            guard let self = self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                // If path has at least 2 items (original_top, new_destination), remove original_top.
                if self.path.count >= 2 {
                    self.path.remove(at: self.path.count - 2)
                }
            }
        }
    }
    
    public func replacingPush<Content: View>(@ViewBuilder _ destination: @escaping () -> Content) {
        // Check current path state to decide strategy. Router is @MainActor.
        if self.path.isEmpty {
            // Use the new method for root replacement if path is empty
            executeOperation { [weak self] in
                self?.replaceRootWithAnimation(destination)
            }
        } else {
            executeOperation {
                self.path.append(DestinationWrapper(destination: AnyView(destination())))
                self.path.remove(at: self.path.count - 3)
            }
        }
    }
    
    public func removeAllPush<Content: View>(@ViewBuilder _ destination: @escaping () -> Content) {
        // Replace the entire navigation stack with the new destination as the root, animated as a push.
        // Use the new method for root replacement
        executeOperation { [weak self] in
            self?.replaceRootWithAnimation(destination)
        }
    }
    
    public func pop() {
        executeOperation { [weak self] in
            guard let self = self else {
                print("❌ [POP] Router is nil, operation cancelled")
                return
            }
            let routerId = ObjectIdentifier(self)
            print("🔙 [POP] Router(\(routerId)) - Current path: \(path.count)")
            
            if !path.isEmpty {
                let destination = path.removeLast()
                SwipeConfiguration.backSwipeAvailable = destination.allowsBackSwipe
                print("✅ [POP] Router(\(routerId)) - Popped. New path: \(path.count)")
            } else {
                print("⚠️ [POP] Router(\(routerId)) - Path empty, nothing to pop")
            }
        }
    }
    
    public func popToRoot() {
        executeOperation { [weak self] in
            guard let self = self else { return }
            path.removeAll()
        }
    }
    
    // MARK: - Sheets & Covers
    public func present<Content: View>(@ViewBuilder _ destination: @escaping () -> Content, onDismiss: (() -> Void)? = nil) {
        executeOperation { [weak self] in
            guard let self = self else {
                print("❌ [PRESENT] Router is nil, operation cancelled")
                return
            }
            
            guard !isPresenting else {
                printAlreadyPresenting()
                return
            }
            
            let routerId = ObjectIdentifier(self)
            let hasParent = parent != nil
            print("🟣 [PRESENT] Router(\(routerId)) hasParent=\(hasParent) - Setting fullscreen")
            onFullScreenDismiss = onDismiss
            let newRouter = Router(parent: self, routerStack: routerStack, root: destination)
            self.fullScreenDestination = newRouter
        }
    }
    
    public func sheet<Content: View>(@ViewBuilder _ destination: @escaping () -> Content, onDismiss: (() -> Void)? = nil) {
        executeOperation { [weak self] in
            guard let self = self else {
                print("❌ [SHEET] Router is nil, operation cancelled")
                return
            }
            
            guard !isPresenting else {
                printAlreadyPresenting()
                return
            }
            
            let routerId = ObjectIdentifier(self)
            let hasParent = parent != nil
            print("🟡 [SHEET] Router(\(routerId)) hasParent=\(hasParent) - Setting sheet")
            onSheetDismiss = onDismiss
            let newRouter = Router(parent: self, routerStack: routerStack, root: destination)
            sheetDestination = newRouter
        }
    }
    
    public func dismiss() {
        executeOperation { [weak self] in
            guard let self = self else {
                print("❌ [DISMISS] Router is nil, operation cancelled")
                return
            }
            
            // Silently ignore dismiss if no parent (root view)
            guard parent != nil else {
                return
            }
            let routerId = ObjectIdentifier(self)
            let parentId = parent.map { ObjectIdentifier($0) }
            
            routerStack.pop(self)
            
            print("🔴 [DISMISS] Router(\(routerId)) - Dismissing from parent(\(String(describing: parentId)))")
            if parent?.sheetDestination != nil {
                parent?.sheetDestination = nil
                print("✅ [DISMISS] Router(\(routerId)) - Cleared parent's sheet")
                return
            }
            if parent?.fullScreenDestination != nil {
                parent?.fullScreenDestination = nil
                print("✅ [DISMISS] Router(\(routerId)) - Cleared parent's fullscreen")
                return
            }
            print("⚠️ [DISMISS] Router(\(routerId)) - No parent destination to clear")
        }
    }
    
    public func dismissPresented() {
        executeOperation { [weak self] in
            guard let self = self else {
                print("❌ [DISMISS] Router is nil, operation cancelled")
                return
            }
            
            if sheetDestination != nil {
                sheetDestination?.dismiss()
            } else if fullScreenDestination != nil {
                fullScreenDestination?.dismiss()
            } else {
                print("⚠️ [DISMISS] Router(\(ObjectIdentifier(self))) - No presented view to dismiss")
            }
        }
    }
    
    public func dismissToRoot() {
        executeOperation { [weak self] in
            guard let self = self else { return }
            
            sheetDestination = nil
            fullScreenDestination = nil
            if let parent = parent {
                parent.dismissToRoot()
            }
        }
    }
}


extension Router {
    func printAlreadyPresenting() {
        if sheetDestination != nil {
            print("❌ [PRESENT] Router already present a sheet, you cannot present other view while presenting sheet")
            return
        }
        
        if fullScreenDestination != nil {
            print("❌ [PRESENT] Router already present a fullcreen cover, you cannot present other view while fullcreen cover")
            return
        }
    }
}
