// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LabStore",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "LabStore", targets: ["LabStore"]),
    ],
    dependencies: [
        .package(path: "../LabDomain"),
    ],
    targets: [
        .target(
            name: "LabStore",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "LabStoreTests",
            dependencies: ["LabStore", .product(name: "LabDomain", package: "LabDomain")]
        ),
    ]
)
