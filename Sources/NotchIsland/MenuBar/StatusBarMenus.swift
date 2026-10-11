import AppKit

/// Меню значков в строке меню — у каждого своё, только кнопки:
/// открыть свой раздел («Мониторинг системы» на нужной вкладке, настройки аккумулятора, лимиты
/// на claude.ai), «Спрятать», «Настройки» и «Выйти из NotchIsland». У zzz — сроки режима
extension StatusBarController {
    enum MenuKind {
        case app, awake
        case stat(Stat)
        case claude(ClaudeWidget)
    }

    /// Содержимое собирается заново при каждом открытии
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch menuKinds[ObjectIdentifier(menu)] ?? .app {
        case .app:
            // значок приложения виден, только когда других нет; вернуть — в настройках, «Строка меню»
            _ = addItem(to: menu, "Спрятать", #selector(hideAppIcon))
        case .awake:
            awake.fill(menu, header: false)
        case .stat(let s):
            if s == .battery {
                _ = addItem(to: menu, "Открыть настройки аккумулятора", #selector(openBatterySettings))
            } else {
                let open = addItem(to: menu, "Открыть «Мониторинг системы»", #selector(openActivityMonitor(_:)))
                open.representedObject = s.rawValue
            }
            let hide = addItem(to: menu, "Спрятать", #selector(toggleStat(_:)))
            hide.representedObject = s.rawValue
        case .claude(let w):
            if usage.needsAccount {
                _ = addItem(to: menu, "Подключить Claude", #selector(connectClaude))
            }
            _ = addItem(to: menu, "Открыть лимиты на claude.ai", #selector(openClaudeUsage))
            let hide = addItem(to: menu, "Спрятать", #selector(toggleClaude(_:)))
            hide.representedObject = w.rawValue
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        _ = addItem(to: menu, "Настройки", #selector(showSettings))
        menu.addItem(NSMenuItem(title: "Выйти из NotchIsland", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))
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

    @objc func hideAppIcon() { statsSettings.showAppIcon = false }

    /// Включаем аккаунт или запускаем вход и показываем, как идёт подключение, — в настройках острова
    @objc func connectClaude() {
        usage.connect()
        openSettings?()
    }

    @objc func openActivityMonitor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = Stat(rawValue: raw) else { return }
        ActivityMonitor.open(ActivityMonitor.tab(for: s))
    }

    @objc func openClaudeUsage() {
        if let url = URL(string: "https://claude.ai/settings/usage") { NSWorkspace.shared.open(url) }
    }

    @objc func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
