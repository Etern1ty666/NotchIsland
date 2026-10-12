import AppKit

// NotchIsland — плавающий «остров» у выреза камеры (macOS 13+). Сборка: ./build.sh
//
// Задержи курсор на вырезе на полсекунды или кликни по нему — остров раскрывается:
//   • Буфер обмена: текст, ссылки, картинки, файлы и свежие скриншоты — клик = скопировать обратно,
//     перетаскивание = в другое окно
//   • Статистика: процессор, память, сеть, диск, батарея и лимиты подписки Claude — клик = подробности
// В строке меню — статистики, закреплённые булавкой на карточке, каждая отдельным значком.

@main
struct NotchIslandMain {
    @MainActor
    static func main() {
        // прежние версии подключались строкой состояния Claude Code; если она ещё вызывает нас
        // (до первого запуска новой версии, которая её отключит), тихо выходим, а не открываем второй остров
        if CommandLine.arguments.contains("--statusline") { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()   // держим сильную ссылку: app.delegate — weak
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
