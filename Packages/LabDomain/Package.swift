// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LabDomain",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "LabDomain", targets: ["LabDomain"]),
    ],
    targets: [
        .target(name: "LabDomain"),
        .testTarget(name: "LabDomainTests", dependencies: ["LabDomain"]),
    ]
)
