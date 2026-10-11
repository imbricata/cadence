// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CadenceCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "CadenceCore", targets: ["CadenceCore"])
    ],
    targets: [
        .target(name: "CadenceCore")
    ]
)