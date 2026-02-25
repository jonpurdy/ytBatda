// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ytBatda",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ytBatdaApp", targets: ["ytBatdaApp"])
    ],
    targets: [
        .executableTarget(
            name: "ytBatdaApp",
            path: "Sources/YTBatdaApp"
        ),
        .testTarget(
            name: "YTBatdaAppTests",
            dependencies: ["ytBatdaApp"],
            path: "Tests/YTBatdaAppTests"
        )
    ]
)
