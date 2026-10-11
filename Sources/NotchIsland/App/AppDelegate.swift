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

        let updater = Updater()
        self.updater = updater
        let controller = IslandController(stats: stats, statsSettings: statsSettings, usage: usage, updater: updater)
        self.controller = controller
        let statusBar = StatusBarController(stats: stats, statsSettings: statsSettings, usage: usage,
                                            awake: controller.awake)
        statusBar.openSettings = { [weak controller] in controller?.showSettings(at: $0) }
        self.statusBar = statusBar

        // новая версия — полоса с кнопкой и прогрессом внизу острова
        let state = controller.state
        updater.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak updater] _ in
                let show = updater?.showsBar ?? false
                if state.updateBar != show { withAnimation(Metrics.spring) { state.updateBar = show } }
            }
            .store(in: &bag)
    }
}
