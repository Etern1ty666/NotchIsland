import AppKit

/// Меню значков в строке меню — у каждого своё:
/// • статистика и лимит Claude — цифры подробнее, действия и «Убрать из строки меню»;
/// • zzz — сроки «Держать экран включенным»;
/// • значок приложения (виден, когда других нет) — общее меню.
/// Внизу у всех, кроме общего, — подменю «NotchIsland» с общими пунктами и «Выйти»
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
            addGeneral(to: menu)
            menu.addItem(.separator())
            _ = addItem(to: menu, "Открыть «Мониторинг системы»", #selector(openActivityMonitor))
            menu.addItem(.separator())
            addQuit(to: menu)
        case .awake:
            awake.fill(menu, header: true)
            addFooter(to: menu)
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
            addFooter(to: menu)
        case .claude(let w):
            addInfo(to: menu, usage.summary(w))
            menu.addItem(.separator())
            _ = addItem(to: menu, "Обновить лимиты", #selector(refreshClaude))
            let hide = addItem(to: menu, "Убрать из строки меню", #selector(toggleClaude(_:)))
            hide.representedObject = w.rawValue
            addFooter(to: menu)
        }
    }

    /// Общее: какие значки показывать, режим экрана, автозапуск, обновления
    private func addGeneral(to menu: NSMenu) {
        let header = NSMenuItem(title: "Показывать в строке меню", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for s in stats.available {
            let item = addItem(to: menu, s.title, #selector(toggleStat(_:)))
            item.representedObject = s.rawValue
            item.state = statsSettings.pinned.contains(s) ? .on : .off
            item.indentationLevel = 1
        }
        for w in ClaudeWidget.allCases {
            let item = addItem(to: menu, "Claude · " + w.title, #selector(toggleClaude(_:)))
            item.representedObject = w.rawValue
            item.state = statsSettings.pinnedClaude.contains(w) ? .on : .off
            item.indentationLevel = 1
        }
        menu.addItem(.separator())

        let awakeMenu = NSMenuItem(title: KeepAwake.title, action: nil, keyEquivalent: "")
        awakeMenu.state = awake.active ? .on : .off
        awakeMenu.submenu = awake.makeMenu(header: false)
        menu.addItem(awakeMenu)
        LoginItem.shared.refresh()
        let login = addItem(to: menu, "Запускать при входе", #selector(toggleLogin))
        login.state = LoginItem.shared.enabled ? .on : .off
        login.isEnabled = LoginItem.shared.available
        menu.addItem(.separator())
        addUpdates(to: menu)
    }

    private func addUpdates(to menu: NSMenu) {
        if let v = updater.availableVersion {
            _ = addItem(to: menu, "Обновить до версии \(v)", #selector(installUpdate))
        }
        _ = addItem(to: menu, "Проверить обновления…", #selector(checkForUpdates))
        let version = NSMenuItem(title: "NotchIsland \(Updater.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
    }

    /// Низ меню отдельного значка: готовое обновление, общее подменю и выход
    private func addFooter(to menu: NSMenu) {
        menu.addItem(.separator())
        if let v = updater.availableVersion {
            _ = addItem(to: menu, "Обновить до версии \(v)", #selector(installUpdate))
        }
        let general = NSMenu()
        general.autoenablesItems = false
        addGeneral(to: general)
        let app = NSMenuItem(title: "NotchIsland", action: nil, keyEquivalent: "")
        app.submenu = general
        menu.addItem(app)
        addQuit(to: menu)
    }

    private func addQuit(to menu: NSMenu) {
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

    @objc func toggleLogin() {
        LoginItem.shared.set(!LoginItem.shared.enabled)
    }

    @objc func installUpdate() { updater.update() }

    @objc func checkForUpdates() { updater.checkForUpdates() }

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
