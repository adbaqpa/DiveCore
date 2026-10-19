// swift-tools-version: 5.9
import PackageDescription

// DiveCore: tamamen saf Foundation modülü (watchOS bağımsız).
// Böylece algoritma çekirdeği hem watchOS uygulamasında hem de
// `swift test` ile macOS üzerinde test edilebilir.
//
// DiveWatch: yalnızca watchOS'ta derlenen ince donanım adaptör katmanı
// (WatchKit / CoreMotion / CoreLocation). macOS'ta `#if canImport` koruması
// sayesinde boş bir modül olarak derlenir.
let package = Package(
    name: "DiveCore",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "DiveCore", targets: ["DiveCore"]),
        .library(name: "DiveWatch", targets: ["DiveWatch"]),
        .library(name: "DiveWatchUI", targets: ["DiveWatchUI"]),
        .library(name: "DiveStore", targets: ["DiveStore"]),
        .library(name: "DiveCharts", targets: ["DiveCharts"]),
        .library(name: "DivePhoneUI", targets: ["DivePhoneUI"]),
        .library(name: "DiveCommerce", targets: ["DiveCommerce"])
    ],
    targets: [
        .target(
            name: "DiveCore",
            path: "Sources/DiveCore"
        ),
        .target(
            name: "DiveWatch",
            dependencies: ["DiveCore"],
            path: "Sources/DiveWatch"
        ),
        .target(
            name: "DiveStore",
            dependencies: ["DiveCore"],
            path: "Sources/DiveStore"
        ),
        .target(
            name: "DiveCharts",
            dependencies: ["DiveCore"],
            path: "Sources/DiveCharts"
        ),
        .target(
            name: "DiveCommerce",
            dependencies: ["DiveCore"],
            path: "Sources/DiveCommerce"
        ),
        .target(
            name: "DivePhoneUI",
            dependencies: ["DiveCore", "DiveCharts", "DiveCommerce"],
            path: "Sources/DivePhoneUI"
        ),
        .target(
            name: "DiveWatchUI",
            dependencies: ["DiveCore", "DiveWatch", "DiveCommerce"],
            path: "Sources/DiveWatchUI"
        ),
        .executableTarget(
            name: "DiveCheck",
            dependencies: ["DiveCore"],
            path: "Tools/DiveCheck"
        ),
        .executableTarget(
            name: "PlistCheck",
            dependencies: ["DiveCore"],
            path: "Tools/PlistCheck"
        ),
        .testTarget(
            name: "DiveCoreTests",
            dependencies: ["DiveCore"],
            path: "Tests/DiveCoreTests"
        )
    ]
)