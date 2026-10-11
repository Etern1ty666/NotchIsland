import AppKit

/// Запуск: установка в /Applications, остров у выреза и значки в строке меню
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let stats = SystemStats()
    let statsSettings = StatsSettings()
    let usage = ClaudeUsage()
    var controller: IslandController?
    var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // --dev: режим разработки, ничего не устанавливаем и не трогаем автозапуск
        let isDev = CommandLine.arguments.contains("--dev")
        if !isDev {
            guard Installer.moveToApplicationsIfNeeded() else { return }
            Installer.enableAutostartOnce()
        }

        let controller = IslandController(stats: stats, statsSettings: statsSettings, usage: usage)
        self.controller = controller
        statusBar = StatusBarController(stats: stats, statsSettings: statsSettings, usage: usage, awake: controller.awake)
    }
}
