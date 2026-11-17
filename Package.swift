// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FinderHotKey",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "FinderHotKey", targets: ["FinderHotKey"])
    ],
    targets: [
        .executableTarget(
            name: "FinderHotKey",
            path: "Sources/FinderHotKey"
        )
    ]
)