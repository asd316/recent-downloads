// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RecentDownloads",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "RecentDownloads",
            dependencies: ["RecentDownloadsCore"]
        ),
        .executableTarget(
            name: "ScannerTestRunner",
            dependencies: ["RecentDownloadsCore"]
        ),
        .target(
            name: "RecentDownloadsCore",
            path: "Sources/RecentDownloadsCore"
        ),
        .testTarget(
            name: "RecentDownloadsTests",
            dependencies: ["RecentDownloadsCore"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ]
        ),
    ]
)