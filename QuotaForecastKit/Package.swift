// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuotaForecastKit",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9)],
    products: [
        .library(name: "QuotaForecastKit", targets: ["QuotaForecastKit"]),
        .executable(name: "quota-forecast", targets: ["QuotaForecastCLI"]),
    ],
    targets: [
        .target(name: "QuotaForecastKit"),
        .executableTarget(name: "QuotaForecastCLI", dependencies: ["QuotaForecastKit"]),
        .testTarget(name: "QuotaForecastKitTests", dependencies: ["QuotaForecastKit"]),
    ]
)
