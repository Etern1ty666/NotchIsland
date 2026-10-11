import AppKit

/// Меню значков в строке меню — у каждого своё:
/// • статистика и лимит Claude — цифры подробнее, действие и «Убрать из строки меню»;
/// • zzz — сроки «Держать экран включенным».
/// Общее (какие значки показывать, автозапуск, обновления) — в настройках острова,
/// внизу каждого меню — «Настройки…» и «Выйти»
extension StatusBarController {
    enum MenuKind {
        case app, awake
        case stat(Stat)
        case claude(ClaudeWidget)
    }

    /// Содержимое собирается заново при каждом открытии — цифры всегда свежие
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch menuKinds[ObjectIdentifier(menu)] ?? .app {
        case .app:
            // значок приложения виден, только когда других нет: остаётся дорога в настройки
            break
        case .awake:
            awake.fill(menu, header: true)
        case .stat(let s):
            addInfo(to: menu, stats.summary(s))
            menu.addItem(.separator())
            if s == .battery {
                _ = addItem(to: menu, "Настройки аккумулятора…", #selector(openBatterySettings))
            } else {
                _ = addItem(to: menu, "Открыть «Мониторинг системы»", #selector(openActivityMonitor))
            }
            let hide = addItem(to: menu, "Убрать из строки меню", #selector(toggleStat(_:)))
            hide.representedObject = s.rawValue
        case .claude(let w):
            addInfo(to: menu, usage.summary(w))
            menu.addItem(.separator())
            _ = addItem(to: menu, "Обновить лимиты", #selector(refreshClaude))
            let hide = addItem(to: menu, "Убрать из строки меню", #selector(toggleClaude(_:)))
            hide.representedObject = w.rawValue
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        _ = addItem(to: menu, "Настройки…", #selector(showSettings))
        menu.addItem(withTitle: "Выйти из NotchIsland", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// Строка-подпись: цифры, не нажимается
    private func addInfo(to menu: NSMenu, _ text: String) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: Действия

    @objc func toggleStat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = Stat(rawValue: raw) else { return }
        statsSettings.toggle(s)
    }

    @objc func toggleClaude(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let w = ClaudeWidget(rawValue: raw) else { return }
        statsSettings.toggle(w)
    }

    @objc func showSettings() { openSettings?() }

    @objc func refreshClaude() { usage.refresh() }

    @objc func openActivityMonitor() {
        SystemStats.openActivityMonitor()
    }

    @objc func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
