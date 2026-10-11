import AppKit
import SwiftUI
import Combine

/// Запуск: установка в /Applications, остров у выреза, значки в строке меню и обновления
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let stats = SystemStats()
    let statsSettings = StatsSettings()
    let usage = ClaudeUsage()
    var controller: IslandController?
    var statusBar: StatusBarController?
    var updater: Updater?
    var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // --dev: режим разработки, ничего не устанавливаем и не трогаем автозапуск
        let isDev = CommandLine.arguments.contains("--dev")
        if !isDev {
            guard Installer.moveToApplicationsIfNeeded() else { return }
            Installer.enableAutostartOnce()
        }

        let controller = IslandController(stats: stats, statsSettings: statsSettings, usage: usage)
        self.controller = controller
        let updater = Updater()
        self.updater = updater
        statusBar = StatusBarController(stats: stats, statsSettings: statsSettings, usage: usage,
                                        awake: controller.awake, updater: updater)

        // новая версия — зелёная кнопка внизу острова
        let state = controller.state
        state.installUpdate = { [weak updater] in updater?.update() }
        updater.$availableVersion
            .receive(on: DispatchQueue.main)
            .sink { v in withAnimation(Metrics.spring) { state.updateVersion = v } }
            .store(in: &bag)
    }
}
