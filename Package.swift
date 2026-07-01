// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingAudioCapture",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MeetingAudioCapture", targets: ["MeetingAudioCapture"])
    ],
    targets: [
        .executableTarget(name: "MeetingAudioCapture"),
        .testTarget(
            name: "MeetingAudioCaptureTests",
            dependencies: ["MeetingAudioCapture"]
        )
    ]
)
