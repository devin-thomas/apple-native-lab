// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LabFeatures",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "LabCatalog", targets: ["LabCatalog"]),
    ],
    dependencies: [
        .package(path: "../LabSupport"),
    ],
    targets: [
        .target(
            name: "LabCatalog",
            dependencies: [.product(name: "LabSupport", package: "LabSupport")],
            resources: [.copy("Resources/experiments.json")]
        ),
        .testTarget(name: "LabCatalogTests", dependencies: ["LabCatalog"]),
    ]
)
