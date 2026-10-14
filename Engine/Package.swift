// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClassicalKeyboardEngine",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ClassicalKeyboardEngine", targets: ["ClassicalKeyboardEngine"]),
    ],
    targets: [
        .target(name: "ClassicalKeyboardEngine", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "kbdemo", dependencies: ["ClassicalKeyboardEngine"]),
        .testTarget(name: "ClassicalKeyboardEngineTests", dependencies: ["ClassicalKeyboardEngine"]),
    ]
)
