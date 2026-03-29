// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Perth",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Perth",
            path: "Sources/Perth",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("AppKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Perth/Info.plist",
                ]),
            ]
        ),
        // Requires Xcode (not just Command Line Tools) for XCTest
        // .testTarget(
        //     name: "PerthTests",
        //     dependencies: ["Perth"],
        //     path: "Tests/PerthTests"
        // ),
    ],
    swiftLanguageModes: [.v6]
)
