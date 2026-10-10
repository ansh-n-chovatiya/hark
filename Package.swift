// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hark",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Runs the Parakeet speech model on this Mac. Apple's own recogniser misheard names and
        // accents too often (decision 0009).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .target(name: "HarkCore"),
        .target(
            name: "HarkMac",
            dependencies: ["HarkCore", .product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(name: "hark", dependencies: ["HarkCore", "HarkMac"], path: "Sources/Hark"),
        .testTarget(name: "HarkCoreTests", dependencies: ["HarkCore"]),
        .testTarget(name: "HarkMacTests", dependencies: ["HarkMac", "HarkCore"]),
    ]
)
