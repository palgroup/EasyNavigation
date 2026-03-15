// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EasyNavigation",
    platforms: [.iOS(.v18)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EasyNavigation",
            targets: ["EasyNavigation"]),
    ],
    targets: [
        .target(
            name: "EasyNavigation"),
        .testTarget(
            name: "EasyNavigationTests",
            dependencies: ["EasyNavigation"]),
    ]
)
