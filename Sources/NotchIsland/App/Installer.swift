import AppKit

/// Установка в «Программы» и автозапуск при первом запуске
@MainActor
enum Installer {
    /// Первый запуск не из /Applications: предлагаем скопировать себя туда и перезапуститься.
    /// Возвращает false, если текущий процесс надо завершить (запущена установленная копия).
    static func moveToApplicationsIfNeeded() -> Bool {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app"), !path.hasPrefix("/Applications/") else { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Установить NotchIsland в «Программы»?"
        alert.informativeText = "Приложение будет скопировано в /Applications и добавлено в автозапуск. Автозапуск можно отключить в меню иконки в строке меню."
        alert.addButton(withTitle: "Установить")
        alert.addButton(withTitle: "Не сейчас")
        guard alert.runModal() == .alertFirstButtonReturn else { return true }

        let dest = URL(fileURLWithPath: "/Applications/NotchIsland.app")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: dest)
        } catch {
            let err = NSAlert()
            err.messageText = "Не удалось установить"
            err.informativeText = error.localizedDescription
            err.runModal()
            return true
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return false
    }

    /// Один раз после установки включаем автозапуск. Если пользователь потом выключит — больше не трогаем.
    static func enableAutostartOnce() {
        guard LoginItem.shared.available,
              !UserDefaults.standard.bool(forKey: DefaultsKey.autostartInitialized) else { return }
        LoginItem.shared.set(true)
        UserDefaults.standard.set(true, forKey: DefaultsKey.autostartInitialized)
    }
}
