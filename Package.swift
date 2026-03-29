// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "iQualize",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "iQualize",
            path: "Sources/iQualize",
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
                    "-Xlinker", "Sources/iQualize/Info.plist",
                ]),
            ]
        ),
        // Requires Xcode (not just Command Line Tools) for XCTest
        // .testTarget(
        //     name: "iQualizeTests",
        //     dependencies: ["iQualize"],
        //     path: "Tests/iQualizeTests"
        // ),
    ],
    swiftLanguageModes: [.v6]
)
