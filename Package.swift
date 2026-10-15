// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UsageRings",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "UsageRings", targets: ["UsageRings"]),
        .executable(name: "UsageRingsStatusline", targets: ["UsageRingsStatusline"]),
        .executable(name: "usage-rings", targets: ["UsageRingsCLI"]),
        .executable(name: "UsageRingsWidget", targets: ["UsageRingsWidget"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "UsageCore", resources: [.copy("Resources")]),
        .executableTarget(name: "UsageRings", dependencies: [
            "UsageCore",
            .product(name: "Sparkle", package: "Sparkle")
        ]),
        .executableTarget(name: "UsageRingsStatusline", dependencies: ["UsageCore"]),
        .executableTarget(name: "UsageRingsCLI", dependencies: ["UsageCore"]),
        .executableTarget(name: "WidgetPreview", dependencies: ["UsageCore"], path: "Tools/WidgetPreview"),
        .executableTarget(
            name: "UsageRingsWidget", dependencies: ["UsageCore"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .testTarget(name: "UsageRingsTests", dependencies: ["UsageRings", "UsageCore", "UsageRingsCLI"])
    ]
)
