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
        .library(name: "AchievementCore", targets: ["AchievementCore"]),
        .library(name: "SpeechCore", targets: ["SpeechCore"]),
        .library(name: "RetrievalCore", targets: ["RetrievalCore"]),
        .library(name: "ContextRouting", targets: ["ContextRouting"]),
        .library(name: "ContextEngineering", targets: ["ContextEngineering"]),
        .library(name: "AgentRuntime", targets: ["AgentRuntime"]),
        .library(name: "ReaderAgent", targets: ["ReaderAgent"]),
        .library(name: "ModelProviders", targets: ["ModelProviders"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "AppInfrastructure", targets: ["AppInfrastructure"]),
        .library(name: "BenchCore", targets: ["BenchCore"]),
        .executable(name: "readloop-bench", targets: ["readloop-bench"]),
        .executable(name: "readloop-bench-compare", targets: ["readloop-bench-compare"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "LibraryCore"),
        .target(name: "ReaderCore", dependencies: ["LibraryCore"]),
        .target(name: "ReadingSessionCore", dependencies: ["LibraryCore", "ReaderCore"]),
        .target(name: "ReflectionCore", dependencies: ["LibraryCore", "ReaderCore", "ReadingSessionCore", "RetrievalCore"]),
        .target(name: "SpeechCore"),
        .target(name: "AgentRuntime"),
        .target(name: "ContextRouting", dependencies: ["AgentRuntime", "LibraryCore"]),
        .target(name: "AchievementCore", dependencies: ["LibraryCore", "ReflectionCore"]),
        .target(name: "RetrievalCore", dependencies: ["LibraryCore", "ReaderCore"]),
        .target(name: "ContextEngineering", dependencies: ["ContextRouting", "RetrievalCore", "ReflectionCore", "ReaderCore", "LibraryCore"]),
        .target(name: "ReaderAgent", dependencies: ["AgentRuntime", "ContextRouting", "ContextEngineering", "ReaderCore", "ReflectionCore", "RetrievalCore"]),
        .target(name: "ModelProviders", dependencies: ["AgentRuntime", "RetrievalCore"]),
        .target(
            name: "Persistence",
            dependencies: [
                "LibraryCore", "ReaderCore", "ReadingSessionCore", "ReflectionCore", "AchievementCore", "RetrievalCore", "ModelProviders", "ContextRouting",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(name: "AppInfrastructure", dependencies: ["LibraryCore", "ReaderCore"]),
        .target(
            name: "BenchCore",
            dependencies: [
                "AgentRuntime", "ContextEngineering", "ContextRouting", "LibraryCore",
                "ModelProviders", "ReaderAgent", "ReaderCore", "ReflectionCore", "RetrievalCore",
            ]
        ),
        .executableTarget(name: "readloop-bench", dependencies: ["BenchCore"]),
        .executableTarget(name: "readloop-bench-compare", dependencies: ["BenchCore"]),
        .testTarget(
            name: "ReadLoopCoreTests",
            dependencies: [
                "LibraryCore", "ReaderCore", "ReadingSessionCore", "ReflectionCore", "AchievementCore", "SpeechCore", "RetrievalCore", "ContextRouting",
                "ContextEngineering", "AgentRuntime", "ReaderAgent", "ModelProviders", "Persistence", "AppInfrastructure",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "AgentProviderTests",
            dependencies: ["AgentRuntime", "ReaderAgent", "ModelProviders", "ReflectionCore", "LibraryCore", "ContextRouting", "ContextEngineering", "RetrievalCore"]
        ),
        .testTarget(
            name: "AgentRuntimeTests",
            dependencies: ["AgentRuntime"]
        ),
        .testTarget(
            name: "BenchCoreTests",
            dependencies: ["BenchCore", "AgentRuntime", "ReaderAgent", "ContextEngineering", "ContextRouting", "ReflectionCore"]
        ),
    ]
)
