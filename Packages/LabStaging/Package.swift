// swift-tools-version: 6.2
import PackageDescription

// The file-system side of import staging: the staging folder a share extension writes and the
// app reads, and the bounded ZIP reader. The policy it enforces lives in LabDomain. It uses only
// system frameworks (Foundation, CryptoKit through LabDomain, Compression) and no third-party code.
let package = Package(
    name: "LabStaging",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "LabStaging", targets: ["LabStaging"]),
    ],
    dependencies: [
        .package(path: "../LabDomain"),
    ],
    targets: [
        .target(
            name: "LabStaging",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "LabStagingTests",
            dependencies: ["LabStaging", .product(name: "LabDomain", package: "LabDomain")]
        ),
    ]
)
