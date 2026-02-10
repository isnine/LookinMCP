// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LookinMCP",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "LookinMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                "LookinShared",
            ]
        ),
        .target(
            name: "LookinShared",
            dependencies: [],
            publicHeadersPath: "include",
            cSettings: [
                .define("SHOULD_COMPILE_LOOKIN_SERVER", to: "1"),
                .headerSearchPath("."),
                .headerSearchPath("Peertalk"),
                .headerSearchPath("Category"),
            ]
        ),
    ]
)
