// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Without Xcode, swift-testing comes from the Command Line Tools and must be linked explicitly.
// With Xcode (e.g. GitHub Actions runners) those flags pull in a mismatched Testing.framework,
// so they are only added on a CLT-only machine outside CI.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let useCLTTesting = ProcessInfo.processInfo.environment["CI"] == nil
    && FileManager.default.fileExists(atPath: cltFrameworks + "/Testing.framework")

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
            swiftSettings: useCLTTesting ? [.unsafeFlags(["-F", cltFrameworks])] : [],
            linkerSettings: useCLTTesting ? [
                .unsafeFlags([
                    "-F", cltFrameworks,
                    "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ] : []
        ),
    ]
)