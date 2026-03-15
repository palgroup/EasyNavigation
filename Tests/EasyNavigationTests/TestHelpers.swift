//
//  TestHelpers.swift
//  EasyNavigationTests
//

import Foundation

/// Waits for Router's AsyncStream operations to process.
/// Uses a small sleep to allow the RunLoop to commit changes.
@MainActor
func waitForRouterOperations(count: Int = 1) async {
    // Each operation needs a yield cycle to process through AsyncStream
    for _ in 0..<(count + 2) {
        await Task.yield()
    }
    // Small sleep to ensure RunLoop processes all pending work
    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
}
