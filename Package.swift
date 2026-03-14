// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mosby",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        .package(url: "https://github.com/christopherkarani/Wax", from: "0.1.17"),
    ],
    targets: [
        .executableTarget(
            name: "Mosby",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Wax", package: "Wax"),
            ],
            path: "Sources/CustomTerminal",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
