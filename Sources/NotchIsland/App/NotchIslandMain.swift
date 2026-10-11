import AppKit

// NotchIsland — плавающий «остров» у выреза камеры (macOS 13+). Сборка: ./build.sh
//
// Задержи курсор на вырезе на полсекунды или кликни по нему — остров раскрывается:
//   • Буфер обмена: текст, ссылки, картинки, файлы и свежие скриншоты — клик = скопировать обратно,
//     перетаскивание = в другое окно, булавка = закрепить навсегда
//   • Статистика: процессор, память, сеть, диск, батарея и лимиты подписки Claude
// В строке меню — закреплённые статистики, каждая отдельным значком.
//
// `NotchIsland --statusline` — режим строки состояния Claude Code (см. ClaudeUsage.runStatusLine)

@main
struct NotchIslandMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--statusline") {
            ClaudeUsage.runStatusLine()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()   // держим сильную ссылку: app.delegate — weak
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
