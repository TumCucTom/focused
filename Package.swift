// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Focused",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FocusedCore", targets: ["FocusedCore"]),
        .executable(name: "Focused", targets: ["FocusedApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "FocusedCore",
            dependencies: []
        ),
        .executableTarget(
            name: "FocusedApp",
            dependencies: [
                "FocusedCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(
            name: "FocusedCoreTests",
            dependencies: ["FocusedCore"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
