// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v13)],
    targets: [
        // Приложение собирается в .app скриптом build.sh: Info.plist и иконка — в Resources/
        .executableTarget(name: "NotchIsland")
    ]
)
