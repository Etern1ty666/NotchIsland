import Foundation

/// Где приложение хранит свои файлы
enum AppPaths {
    /// ~/Library/Application Support/NotchIsland — лимиты Claude, история буфера
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchIsland", isDirectory: true)
}

/// Ключи настроек в UserDefaults — в одном месте, чтобы не разъехались
enum DefaultsKey {
    /// Значки, закреплённые в строке меню, в порядке закрепления (первый — крайний справа)
    static let menuOrder = "menuOrder"
    /// Прежние наборы без порядка — только чтобы перенести их в menuOrder
    static let menuStats = "menuStats"
    static let menuClaude = "menuClaude"
    /// Тёмная подложка под значками в строке меню; без неё значки подстраиваются под строку
    static let menuPill = "menuPill"
    /// Обычный ток зарядки и разряда (мА) — чтобы сразу после подключения или отключения зарядки
    /// показать примерное время, пока macOS его не посчитала
    static let chargeCurrent = "batteryChargeCurrent"
    static let drainCurrent = "batteryDrainCurrent"
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
