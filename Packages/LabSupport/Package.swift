// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LabSupport",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "LabSupport", targets: ["LabSupport"]),
    ],
    targets: [
        .target(name: "LabSupport"),
        .testTarget(name: "LabSupportTests", dependencies: ["LabSupport"]),
    ]
)
