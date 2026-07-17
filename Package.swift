// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScrollProbe",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "ScrollProbe", targets: ["ScrollProbeApp"]),
    ],
    targets: [
        .target(
            name: "ScrollProbeCore",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "ScrollProbeApp",
            dependencies: ["ScrollProbeCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "ScrollProbeCoreTests",
            dependencies: ["ScrollProbeCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
