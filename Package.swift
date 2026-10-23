// swift-tools-version: 6.0
// Package SwiftPM : AVECore (Domain, réseau, stockage, comptes) et AVEKit (audio, écrans, Live Activity).
// L'app (AVE/App) et l'extension Live Activity sont des cibles Xcode (project.yml). Tests sur Mac : `swift test`.
import PackageDescription

let package = Package(
    name: "AVECore",
    // iOS 27 minimum (décision du propriétaire, 2026-10-23) : composants les plus récents, aucune branche de compatibilité.
    // Forme texte : `.v27` exigerait un swift-tools-version plus récent. macOS 14 : hôte des tests `swift test`.
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [
        .library(name: "AVECore", targets: ["AVECore"]),
        .library(name: "AVEKit", targets: ["AVEKit"]),
    ],
    targets: [
        .target(
            name: "AVECore",
            path: "AVE",
            exclude: ["Kit", "Core/Audio", "Features", "App", "LiveActivity"],
            sources: ["Domain", "Core/Network", "Core/Storage", "Core/Auth"]  // pur Foundation : pas d'UI, pas d'AVFoundation
        ),
        // AVEKit : brique intégrable (WoYo, TaGa…). Grossira avec l'audio, la session et l'UI partageable.
        .target(
            name: "AVEKit",
            dependencies: ["AVECore"],
            path: "AVE",
            exclude: ["Domain", "Core/Network", "Core/Storage", "Core/Auth", "App", "LiveActivity"],
            // Core/Audio et Features : logique pure partout ; AVFoundation et SwiftUI sous #if os(iOS)
            sources: ["Kit", "Core/Audio", "Features"]
        ),
        .testTarget(
            name: "AVETests",
            dependencies: ["AVECore", "AVEKit"],
            path: "AVETests"
        ),
    ]
)
