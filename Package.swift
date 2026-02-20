// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ytBatda",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ytBatdaApp", targets: ["ytBatdaApp"])
    ],
    targets: [
        .executableTarget(
            name: "ytBatdaApp",
            path: "Sources/YTDLMacApp"
        )
    ]
)
