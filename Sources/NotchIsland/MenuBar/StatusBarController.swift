import AppKit
import SwiftUI
import Combine

/// Значки в строке меню: статистики и лимиты Claude (какие закреплены), «Держать экран включенным»
/// и обычная иконка приложения, когда больше ничего нашего нет. У всех одно меню
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    let stats: SystemStats
    let statsSettings: StatsSettings
    let usage: ClaudeUsage
    let awake: KeepAwake
    let updater: Updater
    /// Каждая статистика — свой значок в строке меню
    var statItems: [Stat: NSStatusItem] = [:]
    /// Лимиты подписки Claude — тоже по значку на окно
    var claudeItems: [ClaudeWidget: NSStatusItem] = [:]
    /// «Держать экран включенным» — отдельный значок, виден, пока режим включён
    var awakeItem: NSStatusItem?
    /// Обычная иконка приложения — только когда в строке меню больше ничего нашего нет
    var appItem: NSStatusItem?
    var bag = Set<AnyCancellable>()

    init(stats: SystemStats, statsSettings: StatsSettings, usage: ClaudeUsage, awake: KeepAwake, updater: Updater) {
        self.stats = stats
        self.statsSettings = statsSettings
        self.usage = usage
        self.awake = awake
        self.updater = updater
        super.init()

        // macOS ставит каждый новый значок левее предыдущих, поэтому создаём справа налево.
        // autosaveName запоминает, куда пользователь перетащил значок с ⌘
        appItem = makeItem("app")
        appItem?.button?.image = Self.makeMenuBarIcon()
        appItem?.button?.toolTip = "NotchIsland"
        awakeItem = makeItem("awake", content: MenuBarAwake(awake: awake))
        for w in ClaudeWidget.allCases.reversed() {
            let item = makeItem("claude.\(w.rawValue)", content: MenuBarClaude(widget: w, usage: usage))
            item.length = ceil(measure(w) + 9)   // запас под двузначные проценты
            claudeItems[w] = item
        }
        for s in Stat.allCases.reversed() {
            let item = makeItem("stat.\(s.rawValue)", content: MenuBarStat(stat: s, stats: stats))
            item.length = ceil(measure(s) + reserve(s))
            statItems[s] = item
        }
        updateStatusItems()

        statsSettings.$pinned
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItems() }
            .store(in: &bag)
        statsSettings.$pinnedClaude
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItems() }
            .store(in: &bag)
        // лимиты меняются раз в пару минут, а «сброс через N мин» в подсказке — со временем
        usage.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.claudeDidUpdate() }
            .store(in: &bag)
        // включили, выключили или сменили срок — значок и его ширина
        awake.$active.combineLatest(awake.$until)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItems() }
            .store(in: &bag)
        // каждый замер: подсказки при наведении и ширина значков (только растёт — без дёрганья соседей)
        stats.$cpu
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.statsDidUpdate() }
            .store(in: &bag)
    }

    private func makeItem(_ name: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        let menu = NSMenu()
        menu.delegate = self   // содержимое собирается заново при каждом открытии
        menu.autoenablesItems = false
        item.menu = menu
        return item
    }

    private func makeItem<V: View>(_ name: String, content: V) -> NSStatusItem {
        let item = makeItem(name)
        if let button = item.button {
            let v = PassthroughHostingView(rootView: content)
            v.frame = button.bounds
            v.autoresizingMask = [.width, .height]
            button.addSubview(v)
        }
        return item
    }

    /// Запас ширины под будущие цифры, чтобы соседние значки не прыгали: только когда число
    /// сейчас однозначное и почти наверняка станет двузначным. Дальше ширина лишь растёт
    private func reserve(_ s: Stat) -> CGFloat {
        switch s {
        case .cpu: return stats.cpu < 0.095 ? 9 : 2
        case .memory: return stats.memFraction < 0.095 ? 9 : 2
        case .network: return 8
        case .disk, .battery: return 2
        }
    }

    /// Ширина «таблетки» с текущими значениями
    private func measure(_ s: Stat) -> CGFloat {
        NSHostingView(rootView: MenuBarStat(stat: s, stats: stats)).fittingSize.width
    }

    private func measure(_ w: ClaudeWidget) -> CGFloat {
        NSHostingView(rootView: MenuBarClaude(widget: w, usage: usage)).fittingSize.width
    }

    func updateStatusItems() {
        let available = stats.available
        for (s, item) in statItems {
            item.isVisible = statsSettings.pinned.contains(s) && available.contains(s)
        }
        for (w, item) in claudeItems {
            item.isVisible = statsSettings.pinnedClaude.contains(w)
        }
        awakeItem?.isVisible = awake.active
        awakeItem?.button?.toolTip = awake.statusText
        awakeItem?.length = ceil(NSHostingView(rootView: MenuBarAwake(awake: awake)).fittingSize.width + 6)
        appItem?.isVisible = !statItems.values.contains { $0.isVisible }
            && !claudeItems.values.contains { $0.isVisible } && awakeItem?.isVisible != true
        statsDidUpdate()
        claudeDidUpdate()
    }

    func claudeDidUpdate() {
        for (w, item) in claudeItems where item.isVisible {
            let width = ceil(measure(w) + 2)
            if width > item.length { item.length = width }
            item.button?.toolTip = usage.summary(w)
        }
    }

    func statsDidUpdate() {
        for (s, item) in statItems where item.isVisible {
            let w = ceil(measure(s) + 2)
            if w > item.length { item.length = w }
            item.button?.toolTip = stats.summary(s)
        }
    }

    /// Иконка-тумблер для строки меню: белая «таблетка» с вырезом-ручкой справа.
    /// Шаблонное изображение: macOS само красит его под светлую/тёмную тему.
    static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 26, height: 11)
        let img = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            let d = rect.height * 0.68
            let inset = rect.height * 0.16
            let knob = NSRect(x: rect.maxX - inset - d, y: (rect.height - d) / 2, width: d, height: d)
            path.append(NSBezierPath(ovalIn: knob))
            path.windingRule = .evenOdd   // круг вырезается из таблетки
            NSColor.black.setFill()
            path.fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Одно и то же меню у всех наших значков
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
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
        _ = addItem(to: menu, "Открыть «Мониторинг системы»", #selector(openActivityMonitor))
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
        if let v = updater.availableVersion {
            _ = addItem(to: menu, "Обновить до версии \(v)", #selector(installUpdate))
        }
        _ = addItem(to: menu, "Проверить обновления…", #selector(checkForUpdates))
        let version = NSMenuItem(title: "NotchIsland \(Updater.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти из NotchIsland", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

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

    @objc func openActivityMonitor() {
        SystemStats.openActivityMonitor()
    }
}
