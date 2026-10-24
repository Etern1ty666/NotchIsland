import AppKit

/// Меню значков в строке меню — у каждого своё: сверху подробные цифры, дальше кнопки:
/// открыть свой раздел («Мониторинг системы» на нужной вкладке, настройки аккумулятора, лимиты
/// на claude.ai), «Спрятать», «Настройки» и «Выйти из NotchIsland». У zzz — сроки режима.
/// Те же подробности — по клику на карточку на острове (cardMenu)
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
            addItem(to: menu, "Спрятать", #selector(hideAppIcon))
        case .awake:
            addHeader(to: menu, [(KeepAwake.title, [awake.remainingText])])
            awake.fill(menu, header: false)
        case .stat(let s):
            addDetails(to: menu, .stat(s))
            addItem(to: menu, "Спрятать", #selector(togglePin(_:))).representedObject = MenuItem.stat(s).key
        case .claude(let w):
            addDetails(to: menu, .claude(w))
            addItem(to: menu, "Спрятать", #selector(togglePin(_:))).representedObject = MenuItem.claude(w).key
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        addItem(to: menu, "Настройки", #selector(showSettings))
        menu.addItem(NSMenuItem(title: L("Выйти из NotchIsland"), action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))
    }

    /// Меню карточки на острове: подробности и кнопки как у её значка, вместо «Спрятать» —
    /// «Показывать в строке меню» с галочкой
    func cardMenu(_ item: MenuItem) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addDetails(to: menu, item)
        menu.addItem(.separator())
        let pin = addItem(to: menu, "Показывать в строке меню", #selector(togglePin(_:)))
        pin.representedObject = item.key
        pin.state = statsSettings.menuOrder.contains(item) ? .on : .off
        return menu
    }

    /// Подробные цифры и «открыть свой раздел»
    private func addDetails(to menu: NSMenu, _ item: MenuItem) {
        switch item {
        case .stat(let s):
            // заголовок: главная цифра жирно, под ней подробности
            addHeader(to: menu, [stats.menuHeader(s)])
            if s == .battery {
                addItem(to: menu, "Открыть настройки аккумулятора", #selector(openBatterySettings))
            } else {
                addItem(to: menu, "Открыть «Мониторинг системы»", #selector(openActivityMonitor(_:)))
                    .representedObject = s.rawValue
            }
        case .claude:
            // заголовок: оба окна — сколько израсходовано и через сколько сброс
            if !usage.needsAccount { addHeader(to: menu, ClaudeWidget.allCases.map(claudeHeader)) }
            // «Обновить» — первой кнопкой, без аккаунта вместо неё «Подключить Claude»
            if usage.needsAccount {
                addItem(to: menu, "Подключить Claude", #selector(connectClaude))
            } else {
                addItem(to: menu, "Обновить", #selector(refreshClaude))
            }
            addItem(to: menu, "Открыть лимиты на claude.ai", #selector(openClaudeUsage))
        }
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

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: L(title), action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: Действия

    /// «Спрятать» у значка и «Показывать в строке меню» у карточки
    @objc func togglePin(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let item = MenuItem(key: key) else { return }
        statsSettings.toggle(item)
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
