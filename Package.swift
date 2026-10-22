// swift-tools-version: 6.0
// Package SwiftPM du cœur testable (Domain + réseau + stockage). L'app SwiftUI, l'audio
// et la Live Activity vivent dans la cible Xcode et ne sont pas dans ce package.
// Lancer les tests sur Mac : `cd ios && swift test`
import PackageDescription

let package = Package(
    name: "AVECore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AVECore", targets: ["AVECore"]),
        .library(name: "AVEKit", targets: ["AVEKit"]),
    ],
    targets: [
        .target(
            name: "AVECore",
            path: "AVE",
            exclude: ["Kit", "Core/Audio"],
            sources: ["Domain", "Core/Network", "Core/Storage"]  // pur Foundation : pas d'UI, pas d'AVFoundation
        ),
        // AVEKit : brique intégrable (WoYo, TaGa…). Grossira avec l'audio, la session et l'UI partageable.
        .target(
            name: "AVEKit",
            dependencies: ["AVECore"],
            path: "AVE",
            exclude: ["Domain", "Core/Network", "Core/Storage"],
            sources: ["Kit", "Core/Audio"]  // Core/Audio : logique pure partout, AVFoundation sous #if os(iOS)
        ),
        .testTarget(
            name: "AVETests",
            dependencies: ["AVECore", "AVEKit"],
            path: "AVETests"
        ),
    ]
)
