import AppKit

/// Меню значков в строке меню — у каждого своё: сверху подробные цифры, дальше кнопки:
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
        Localizer.shared.refresh()
        menu.removeAllItems()
        switch menuKinds[ObjectIdentifier(menu)] ?? .app {
        case .app:
            // значок приложения виден, только когда других нет; вернуть — в настройках, «Строка меню»
            _ = addItem(to: menu, "Спрятать", #selector(hideAppIcon))
        case .awake:
            addHeader(to: menu, [(KeepAwake.title, [awake.remainingText])])
            awake.fill(menu, header: false)
        case .stat(let s):
            // заголовок: главная цифра жирно, под ней подробности
            addHeader(to: menu, [stats.menuHeader(s)])
            if s == .battery {
                _ = addItem(to: menu, "Открыть настройки аккумулятора", #selector(openBatterySettings))
            } else {
                let open = addItem(to: menu, "Открыть «Мониторинг системы»", #selector(openActivityMonitor(_:)))
                open.representedObject = s.rawValue
            }
            let hide = addItem(to: menu, "Спрятать", #selector(toggleStat(_:)))
            hide.representedObject = s.rawValue
        case .claude(let w):
            // заголовок: оба окна — сколько израсходовано и через сколько сброс
            if !usage.needsAccount { addHeader(to: menu, ClaudeWidget.allCases.map(claudeHeader)) }
            if usage.needsAccount {
                _ = addItem(to: menu, "Подключить Claude", #selector(connectClaude))
            } else if usage.window(w) == nil {
                _ = addItem(to: menu, "Обновить", #selector(refreshClaude))
            }
            _ = addItem(to: menu, "Открыть лимиты на claude.ai", #selector(openClaudeUsage))
            let hide = addItem(to: menu, "Спрятать", #selector(toggleClaude(_:)))
            hide.representedObject = w.rawValue
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        _ = addItem(to: menu, "Настройки", #selector(showSettings))
        menu.addItem(NSMenuItem(title: L("Выйти из NotchIsland"), action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))
    }

    /// Окно лимита Claude для заголовка: «Сессия · 5 ч — израсходовано 42%» и «Сброс через 2 ч 10 мин»
    private func claudeHeader(_ w: ClaudeWidget) -> (String, [String]) {
        guard let win = usage.window(w) else {
            return (w.title, [usage.apiError ?? L("Загружаю")])
        }
        let spent = (win.spent * 100).rounded() > 0 ? L("израсходовано %@", pct(win.spent)) : L("лимит не тронут (0%)")
        return (w.title + " — " + spent, [resetText(win.resetsAt).capitalizedFirst])
    }

    /// Текст над кнопками, блоками: заголовок жирно, под ним строки потише; не нажимается
    private func addHeader(to menu: NSMenu, _ groups: [(String, [String])]) {
        for (title, lines) in groups {
            addText(to: menu, title, bold: true)
            lines.forEach { addText(to: menu, $0, bold: false) }
        }
        menu.addItem(.separator())
    }

    private func addText(to menu: NSMenu, _ text: String, bold: Bool) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: bold ? NSFont.menuFont(ofSize: 0).bold : NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: bold ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ])
        menu.addItem(item)
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: L(title), action: action, keyEquivalent: "")
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

    @objc func showSettings() { openSettings?(nil) }

    @objc func hideAppIcon() { statsSettings.showAppIcon = false }

    @objc func refreshClaude() { usage.refresh() }

    /// Включаем аккаунт или запускаем вход и показываем, как идёт подключение, — в настройках острова
    @objc func connectClaude() {
        usage.connect()
        openSettings?(SettingsView.claudeAccount)
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

private extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}
