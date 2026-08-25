// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadLoopCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "LibraryCore", targets: ["LibraryCore"]),
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
        .library(name: "ReadingSessionCore", targets: ["ReadingSessionCore"]),
        .library(name: "ReflectionCore", targets: ["ReflectionCore"]),
        .library(name: "RetrievalCore", targets: ["RetrievalCore"]),
        .library(name: "ContextRouting", targets: ["ContextRouting"]),
        .library(name: "AgentRuntime", targets: ["AgentRuntime"]),
        .library(name: "ReaderAgent", targets: ["ReaderAgent"]),
        .library(name: "ModelProviders", targets: ["ModelProviders"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "AppInfrastructure", targets: ["AppInfrastructure"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "LibraryCore"),
        .target(name: "ReaderCore", dependencies: ["LibraryCore"]),
        .target(name: "ReadingSessionCore", dependencies: ["LibraryCore", "ReaderCore"]),
        .target(name: "ReflectionCore", dependencies: ["LibraryCore", "ReaderCore", "ReadingSessionCore"]),
        .target(name: "AgentRuntime"),
        .target(name: "ContextRouting", dependencies: ["AgentRuntime", "LibraryCore"]),
        .target(name: "RetrievalCore", dependencies: ["LibraryCore", "ReaderCore"]),
        .target(name: "ReaderAgent", dependencies: ["AgentRuntime", "ContextRouting", "ReaderCore", "ReflectionCore", "RetrievalCore"]),
        .target(name: "ModelProviders", dependencies: ["AgentRuntime"]),
        .target(
            name: "Persistence",
            dependencies: [
                "LibraryCore", "ReaderCore", "ReadingSessionCore", "ReflectionCore", "RetrievalCore", "ModelProviders",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(name: "AppInfrastructure", dependencies: ["LibraryCore", "ReaderCore"]),
        .testTarget(
            name: "ReadLoopCoreTests",
            dependencies: [
                "LibraryCore", "ReaderCore", "ReadingSessionCore", "ReflectionCore", "RetrievalCore", "ContextRouting",
                "AgentRuntime", "ReaderAgent", "Persistence", "AppInfrastructure",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "AgentProviderTests",
            dependencies: ["AgentRuntime", "ReaderAgent", "ModelProviders", "ReflectionCore", "LibraryCore", "ContextRouting"]
        ),
        .testTarget(
            name: "AgentRuntimeTests",
            dependencies: ["AgentRuntime"]
        ),
    ]
)
