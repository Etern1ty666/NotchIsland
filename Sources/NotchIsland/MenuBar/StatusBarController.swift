import AppKit
import SwiftUI
import Combine

/// Значки в строке меню: статистики и лимиты Claude (какие закреплены), «Держать экран включенным»
/// (пока режим включён) и значок приложения, когда больше ничего нашего нет (его тоже можно спрятать).
/// Показываются только нужные: при каждом изменении набора значки создаются заново справа налево —
/// так zzz всегда крайний справа среди наших, остальные идут в порядке закрепления и не остаётся пустых мест. У каждого своё меню (StatusBarMenus)
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    let stats: SystemStats
    let statsSettings: StatsSettings
    let usage: ClaudeUsage
    let awake: KeepAwake
    /// Показанные значки статистик
    var statItems: [Stat: NSStatusItem] = [:]
    /// Показанные лимиты подписки Claude — по значку на окно
    var claudeItems: [ClaudeWidget: NSStatusItem] = [:]
    /// «Держать экран включенным» — пока режим включён
    var awakeItem: NSStatusItem?
    /// Значок приложения — когда больше ничего нашего нет
    var appItem: NSStatusItem?
    /// Какие значки сейчас показаны, справа налево
    private var shown: [String] = []
    /// Вид «таблетки» Claude («подключите», «без данных», «с цифрами») — при смене ширина задаётся заново
    private var claudeLooks: [ClaudeWidget: String] = [:]
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

        updateStatusItems()

        statsSettings.$menuOrder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItems() }
            .store(in: &bag)
        statsSettings.$showAppIcon
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
        // сменили язык системы — значки заново: другие подписи и ширина
        Localizer.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.shown = []
                self?.updateStatusItems()
            }
            .store(in: &bag)
        // каждый замер: подсказки при наведении и ширина значков (только растёт — без дёрганья соседей)
        stats.$cpu
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.statsDidUpdate() }
            .store(in: &bag)
    }

    private func makeItem(_ slot: String, kind: MenuKind) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = slot
        let menu = NSMenu()
        menu.delegate = self   // содержимое собирается заново при каждом открытии
        menu.autoenablesItems = false
        menuKinds[ObjectIdentifier(menu)] = kind
        item.menu = menu
        return item
    }

    private func makeItem<V: View>(_ slot: String, kind: MenuKind, content: V) -> NSStatusItem {
        let item = makeItem(slot, kind: kind)
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
        // справа налево: macOS ставит каждый новый значок левее предыдущих
        var wanted: [String] = []
        if awake.active { wanted.append("awake.right") }
        // дальше — в порядке закрепления: первый закреплённый крайний справа
        let available = stats.available
        for item in statsSettings.menuOrder {
            if case .stat(let s) = item, !available.contains(s) { continue }
            wanted.append(item.key)
        }
        if wanted.isEmpty && statsSettings.showAppIcon { wanted = ["app"] }
        if wanted != shown { rebuild(wanted) }

        awakeItem?.button?.toolTip = awake.statusText
        if let awakeItem {
            awakeItem.length = ceil(NSHostingView(rootView: MenuBarAwake(awake: awake)).fittingSize.width + 6)
        }
        statsDidUpdate()
        claudeDidUpdate()
    }

    /// Убираем все наши значки и создаём нужные заново, справа налево.
    /// macOS запоминает место значка по autosaveName и при пересоздании ставит его туда же, а не по
    /// порядку создания. Поэтому имя — номер места справа, а не что в значке: «item.0» всегда крайний
    private func rebuild(_ wanted: [String]) {
        let old = Array(statItems.values) + Array(claudeItems.values) + [awakeItem, appItem].compactMap { $0 }
        old.forEach { NSStatusBar.system.removeStatusItem($0) }
        statItems = [:]
        claudeItems = [:]
        awakeItem = nil
        appItem = nil
        menuKinds = [:]
        claudeLooks = [:]
        for (i, name) in wanted.enumerated() {
            let slot = "item.\(i)"
            if name == "awake.right" {
                awakeItem = makeItem(slot, kind: .awake, content: MenuBarAwake(awake: awake))
            } else if name == "app" {
                let item = makeItem(slot, kind: .app)
                item.button?.image = Self.makeMenuBarIcon()
                item.button?.toolTip = "NotchIsland"
                appItem = item
            } else if case .claude(let w) = MenuItem(key: name) {
                let item = makeItem(slot, kind: .claude(w), content: MenuBarClaude(widget: w, usage: usage))
                item.length = ceil(measure(w) + 9)   // запас под двузначные проценты
                claudeItems[w] = item
            } else if case .stat(let s) = MenuItem(key: name) {
                let item = makeItem(slot, kind: .stat(s), content: MenuBarStat(stat: s, stats: stats))
                item.length = ceil(measure(s) + reserve(s))
                statItems[s] = item
            }
        }
        shown = wanted
    }

    /// Ширина значков Claude: в пределах одного вида только растёт (цифры не дёргают соседей),
    /// а при смене вида — по новому содержимому
    func claudeDidUpdate() {
        for (w, item) in claudeItems {
            let look = usage.needsAccount ? "account" : (usage.window(w) == nil ? "empty" : "data")
            let width = ceil(measure(w) + 2)
            if claudeLooks[w] != look {
                claudeLooks[w] = look
                item.length = look == "data" ? width + 7 : width   // запас под двузначные проценты
            } else if width > item.length {
                item.length = width
            }
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
