import AppKit
import SwiftUI
import Combine

/// Значки в строке меню: статистики и лимиты Claude (какие закреплены), «Держать экран включенным»
/// и обычная иконка приложения, когда больше ничего нашего нет. У каждого своё меню (StatusBarMenus)
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    let stats: SystemStats
    let statsSettings: StatsSettings
    let usage: ClaudeUsage
    let awake: KeepAwake
    /// Каждая статистика — свой значок в строке меню
    var statItems: [Stat: NSStatusItem] = [:]
    /// Лимиты подписки Claude — тоже по значку на окно
    var claudeItems: [ClaudeWidget: NSStatusItem] = [:]
    /// «Держать экран включенным» — отдельный значок, виден, пока режим включён
    var awakeItem: NSStatusItem?
    /// Обычная иконка приложения — только когда в строке меню больше ничего нашего нет
    var appItem: NSStatusItem?
    var bag = Set<AnyCancellable>()
    /// Чьё это меню — по нему menuNeedsUpdate решает, что показать
    var menuKinds: [ObjectIdentifier: MenuKind] = [:]
    /// «Настройки…» — раскрыть остров на настройках
    var openSettings: (() -> Void)?

    init(stats: SystemStats, statsSettings: StatsSettings, usage: ClaudeUsage, awake: KeepAwake) {
        self.stats = stats
        self.statsSettings = statsSettings
        self.usage = usage
        self.awake = awake
        super.init()

        // macOS ставит каждый новый значок левее предыдущих, поэтому создаём справа налево:
        // «Держать экран включенным» — первым, он всегда крайний справа среди наших.
        // autosaveName запоминает, куда пользователь перетащил значок с ⌘
        awakeItem = makeItem("awake.right", kind: .awake, content: MenuBarAwake(awake: awake))
        appItem = makeItem("app", kind: .app)
        appItem?.button?.image = Self.makeMenuBarIcon()
        appItem?.button?.toolTip = "NotchIsland"
        for w in ClaudeWidget.allCases.reversed() {
            let item = makeItem("claude.\(w.rawValue)", kind: .claude(w), content: MenuBarClaude(widget: w, usage: usage))
            item.length = ceil(measure(w) + 9)   // запас под двузначные проценты
            claudeItems[w] = item
        }
        for s in Stat.allCases.reversed() {
            let item = makeItem("stat.\(s.rawValue)", kind: .stat(s), content: MenuBarStat(stat: s, stats: stats))
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

    private func makeItem(_ name: String, kind: MenuKind) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        let menu = NSMenu()
        menu.delegate = self   // содержимое собирается заново при каждом открытии
        menu.autoenablesItems = false
        menuKinds[ObjectIdentifier(menu)] = kind
        item.menu = menu
        return item
    }

    private func makeItem<V: View>(_ name: String, kind: MenuKind, content: V) -> NSStatusItem {
        let item = makeItem(name, kind: kind)
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
        // значок режима не прячем, а сжимаем в ноль: так он держит своё место крайним справа.
        // Спрятанный и снова показанный значок macOS ставит левее всех наших
        awakeItem?.isVisible = true
        awakeItem?.button?.toolTip = awake.active ? awake.statusText : nil
        awakeItem?.length = awake.active
            ? ceil(NSHostingView(rootView: MenuBarAwake(awake: awake)).fittingSize.width + 6) : 0
        appItem?.isVisible = !statItems.values.contains { $0.isVisible }
            && !claudeItems.values.contains { $0.isVisible } && !awake.active
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
}
