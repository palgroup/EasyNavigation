//
//  NavigationLogger.swift
//  EasyNavigation
//
//  Created by EasyNavigation on 2026-03-15.
//

import os

enum NavigationLogger {
    private static let logger = Logger(
        subsystem: "com.seklabs.EasyNavigation",
        category: "Navigation"
    )

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
