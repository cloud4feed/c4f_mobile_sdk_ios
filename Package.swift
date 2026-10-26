// swift-tools-version:5.9
// Cloud4Feed Mobile SDK for iOS.
//
// The core (models, config parsing, cache, rules, value resolution, URL building) only uses
// Foundation, so it also builds and tests on Linux/Windows. UIKit/WebKit code is wrapped in
// `#if canImport(UIKit)` and is added in Phase 2.
import PackageDescription

let package = Package(
    name: "Cloud4FeedSDK",
    platforms: [
        .iOS(.v15),
        // macOS is only declared so `swift test` can run on a Mac host. The SDK targets iOS.
        .macOS(.v12),
    ],
    products: [
        .library(name: "Cloud4FeedSDK", targets: ["Cloud4FeedSDK"]),
    ],
    targets: [
        .target(
            name: "Cloud4FeedSDK",
            path: "Sources/Cloud4FeedSDK",
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "Cloud4FeedSDKTests",
            dependencies: ["Cloud4FeedSDK"],
            path: "Tests/Cloud4FeedSDKTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
