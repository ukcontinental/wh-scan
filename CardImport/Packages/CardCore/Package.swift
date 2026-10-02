// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CardCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CardCore", targets: ["CardCore"]),
        .executable(name: "cardcore-cli", targets: ["CardCoreCLI"]),
    ],
    targets: [
        .target(name: "CardCore"),
        .executableTarget(name: "CardCoreCLI", dependencies: ["CardCore"]),
        .testTarget(name: "CardCoreTests", dependencies: ["CardCore"]),
    ]
)
