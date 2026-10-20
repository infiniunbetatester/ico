// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ICO",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ICO", targets: ["ICO"])
    ],
    targets: [
        .executableTarget(
            name: "ICO",
            path: "Sources"
        )
    ]
)
