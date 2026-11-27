// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Vocality",
    platforms: [.macOS(.v15)],
    dependencies: [
        // ASR + VAD only: TTS, diarization and text normalization are opted out via traits.
        .package(
            url: "https://github.com/FluidInference/FluidAudio",
            revision: "ee78635d23d52379117554ba72358b65a0612447",
            traits: []
        ),
    ],
    targets: [
        .executableTarget(
            name: "Vocality",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Vocality",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
