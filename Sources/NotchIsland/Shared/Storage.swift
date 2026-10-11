import Foundation

/// Где приложение хранит свои файлы
enum AppPaths {
    /// ~/Library/Application Support/NotchIsland — лимиты Claude, история буфера
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchIsland", isDirectory: true)
}

/// Ключи настроек в UserDefaults — в одном месте, чтобы не разъехались
enum DefaultsKey {
    /// Статистики и окна лимитов Claude, закреплённые в строке меню
    static let menuStats = "menuStats"
    static let menuClaude = "menuClaude"
    /// Значок приложения в строке меню (когда других наших нет)
    static let menuAppIcon = "menuAppIcon"
    /// Брать лимиты Claude через вход Claude Code (в настройках можно отключить)
    static let claudeAccount = "claudeAccountEnabled"
    /// Буфер: срок хранения истории
    static let clipRetention = "clipRetention"
    /// Версия, в которой остров уже раскрывали: после установки и каждого обновления
    /// вокруг выреза снова зелёная подсказка
    static let islandHintVersion = "islandHintVersion"
    /// Автозапуск уже включали один раз после установки
    static let autostartInitialized = "autostartInitialized"
}
