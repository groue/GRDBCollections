// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GRDBCollections",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "GRDBCollections",
            targets: ["GRDBCollections"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/groue/GRDB.swift.git", branch: "development"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "GRDBCollections",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]),
        .testTarget(
            name: "GRDBCollectionsTests",
            dependencies: ["GRDBCollections"]),
    ]
)
