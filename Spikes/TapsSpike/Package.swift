// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TapsSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TapsSpike",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFAudio"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/TapsSpike/Info.plist",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
