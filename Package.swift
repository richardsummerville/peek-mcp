// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "peek",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "peek", targets: ["Peek"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "Peek",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "PeekTests",
            dependencies: ["Peek"]
        )
    ]
)
