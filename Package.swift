// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadLoopCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "LibraryCore", targets: ["LibraryCore"]),
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "AppInfrastructure", targets: ["AppInfrastructure"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "LibraryCore"),
        .target(name: "ReaderCore", dependencies: ["LibraryCore"]),
        .target(
            name: "Persistence",
            dependencies: ["LibraryCore", "ReaderCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "AppInfrastructure", dependencies: ["LibraryCore", "ReaderCore"]),
        .testTarget(
            name: "ReadLoopCoreTests",
            dependencies: [
                "LibraryCore", "ReaderCore", "Persistence", "AppInfrastructure",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
