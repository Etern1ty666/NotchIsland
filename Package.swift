// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v13)],
    dependencies: [
        // обновления с сервера: проверка, фоновая загрузка (в том числе только разницы), установка
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Приложение собирается в .app скриптом build.sh: Info.plist и иконка — в Resources/,
        // Sparkle.framework кладётся в Contents/Frameworks
        .executableTarget(
            name: "NotchIsland",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
