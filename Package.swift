// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

import class Foundation.ProcessInfo

let package = Package(
    name: "swift-opa",
    platforms: [
        .macOS(.v15),
        .iOS(.v16),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftOPA",
            targets: ["SwiftOPA"]),
        .executable(
            name: "swift-opa-cli",
            targets: ["CLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0"..<"4.0.0"),
        .package(url: "https://github.com/apple/containerization", from: "0.25.0"),
        //.package(url: "https://github.com/apple/swift-nio-extras", from: "1.32.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftOPA",
            dependencies: ["AST", "IR", "Rego", "SDK"]
        ),
        .target(name: "AST"),
        .target(
            name: "IR",
            dependencies: ["AST"]
        ),
        .target(
            name: "Rego",
            dependencies: [
                "AST",
                "IR",
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ]
        ),
        .target(
            name: "SDK",
            dependencies: [
                "AST",
                "IR",
                "Rego",
                .product(name: "ContainerizationArchive", package: "containerization"),
                //.product(name: "NIOHTTPCompression", package: "swift-nio-extras"),
            ]
        ),
        // Internal module tests
        .testTarget(
            name: "ASTTests",
            dependencies: ["AST"]
        ),
        .testTarget(
            name: "IRTests",
            dependencies: ["IR"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "RegoTests",
            dependencies: ["Rego"],
            resources: [.copy("TestData")]
        ),
        // Public API surface tests
        .testTarget(
            name: "SwiftOPATests",
            dependencies: ["SwiftOPA"]
        ),
        .executableTarget(
            name: "CLI",
            dependencies: [
                "Rego",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
