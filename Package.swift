// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FastWords",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FastWords", targets: ["FastWords"])
    ],
    targets: [
        .target(
            name: "FastWordsCore",
            resources: [
                .copy("Resources/ecdict_exam.tsv")
            ]
        ),
        .executableTarget(
            name: "FastWords",
            dependencies: ["FastWordsCore"],
            resources: [
                .copy("Fonts/MapleMono-Regular.ttf"),
                .copy("Fonts/MapleMono-Bold.ttf")
            ]
        ),
        .testTarget(
            name: "FastWordsCoreTests",
            dependencies: ["FastWordsCore"]
        )
    ]
)
