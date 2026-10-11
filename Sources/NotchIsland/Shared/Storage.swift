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
    /// Буфер: пауза записи и срок хранения незакреплённого
    static let clipPaused = "clipPaused"
    static let clipRetention = "clipRetention"
    /// Автозапуск уже включали один раз после установки
    static let autostartInitialized = "autostartInitialized"
}
