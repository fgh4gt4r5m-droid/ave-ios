// swift-tools-version: 6.0
// Package SwiftPM du cœur testable (Domain + réseau + stockage). L'app SwiftUI, l'audio
// et la Live Activity vivent dans la cible Xcode et ne sont pas dans ce package.
// Lancer les tests sur Mac : `cd ios && swift test`
import PackageDescription

let package = Package(
    name: "AVECore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AVECore", targets: ["AVECore"])],
    targets: [
        .target(
            name: "AVECore",
            path: "AVE",
            sources: ["Domain", "Core/Network", "Core/Storage"]
        ),
        .testTarget(
            name: "AVETests",
            dependencies: ["AVECore"],
            path: "AVETests"
        ),
    ]
)
