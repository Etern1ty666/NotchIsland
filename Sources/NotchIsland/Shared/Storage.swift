import Foundation

/// Где приложение хранит свои файлы
enum AppPaths {
    /// ~/Library/Application Support/NotchIsland — лимиты Claude, история буфера
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchIsland", isDirectory: true)
}

/// Ключи настроек в UserDefaults — в одном месте, чтобы не разъехались
enum DefaultsKey {
    /// Последняя открытая вкладка острова
    static let lastTab = "lastTab"
    /// Статистики и окна лимитов Claude, закреплённые в строке меню
    static let menuStats = "menuStats"
    static let menuClaude = "menuClaude"
    /// Брать лимиты Claude через вход Claude Code (в настройках можно отключить)
    static let claudeAccount = "claudeAccountEnabled"
    /// Буфер: срок хранения истории
    static let clipRetention = "clipRetention"
    /// Автозапуск уже включали один раз после установки
    static let autostartInitialized = "autostartInitialized"
}
