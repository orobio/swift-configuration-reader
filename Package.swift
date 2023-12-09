// swift-tools-version: 5.7

import PackageDescription


var globalSwiftSettings = [SwiftSetting]()
if Context.environment["ENABLE_CONCURRENCY_CHECKS"] != nil {
    globalSwiftSettings.append(.unsafeFlags(["-Xfrontend", "-strict-concurrency=complete"]))
}


let package = Package(
    name: "swift-configuration-reader",
    products: [
        .library(
            name: "ConfigurationReader",
            targets: [
                "ConfigurationReader"
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sersoft-gmbh/swift-inotify.git", from: "0.4.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0-beta.1"),
        .package(url: "https://github.com/Kitura/Configuration.git", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "ConfigurationReader",
            dependencies: [
                .product(name: "Inotify", package: "swift-inotify"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Configuration", package: "Configuration"),
            ],
            swiftSettings: globalSwiftSettings
        ),
        .executableTarget(
            name: "Example",
            dependencies: [
                "ConfigurationReader",
                .product(name: "Configuration", package: "Configuration"),
            ]
        ),
    ]
)
