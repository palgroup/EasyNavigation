//
//  RouterStack.swift
//  EasyNavigation
//
//  Created by Salihcan Kahya on 2.05.2025.
//

import SwiftUI

@Observable
@MainActor
public final class RouterStack {
    public init() {}

    /// Weak wrapper to avoid retain-cycles
    private struct WeakRouter {
        weak var value: Router?
        
        init(value: Router?) {
            self.value = value
        }
        
        var isNil: Bool {
            return value == nil
        }
    }

    @ObservationIgnored
    private var stack: [WeakRouter] = []
    
    @ObservationIgnored
    private var cleanupTask: Task<Void, Never>?
    
    deinit {
        cleanupTask?.cancel()
    }
    
    private func cleanupNilRouters() {
        stack.removeAll { $0.isNil }
    }

    /// Call in `ViewNavigationWrapper.onAppear`
    func push(_ router: Router) {
        cleanupNilRouters()
        
        // Don't add duplicates
        if !stack.contains(where: { $0.value === router }) {
            stack.append(WeakRouter(value: router))
        }
        
        // Setup periodic cleanup if needed
        if cleanupTask == nil {
            // Capture self as unowned since cleanupTask will be cancelled in deinit
            cleanupTask = Task { [unowned self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        await MainActor.run {
                            self.cleanupNilRouters()
                        }
                    } catch {
                        break // Exit on cancellation
                    }
                }
            }
        }
    }

    /// Call in `ViewNavigationWrapper.onDisappear`
    func pop(_ router: Router) {
        stack.removeAll { $0.value === router || $0.isNil }
    }

    /// Router currently on screen (sheet / fullscreen içinde dâhil)
    var topMostRouter: Router? {
        cleanupNilRouters()
        return stack.last?.value
    }
}
