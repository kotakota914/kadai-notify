// swift-tools-version:5.9
// KadaiCore: 画面(SwiftUI)に依存しない「計算だけ」の部品を集めたパッケージ。
// iPhone アプリとウィジェットの両方から使い、Mac のターミナルで `swift test` でテストできる。
import PackageDescription

let package = Package(
    name: "KadaiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KadaiCore", targets: ["KadaiCore"]),
    ],
    targets: [
        .target(name: "KadaiCore"),
        .testTarget(name: "KadaiCoreTests", dependencies: ["KadaiCore"]),
    ]
)
