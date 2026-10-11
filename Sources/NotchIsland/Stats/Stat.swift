import SwiftUI

/// Что умеем показывать: каждая статистика — отдельный значок в строке меню и карточка на острове
enum Stat: String, CaseIterable, Identifiable {
    case cpu, memory, network, disk, battery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: return L("Процессор")
        case .memory: return L("Память")
        case .network: return L("Сеть")
        case .disk: return L("Диск")
        case .battery: return L("Батарея")
        }
    }
}

/// Значок в строке меню, который можно закрепить: статистика или окно лимитов Claude
enum MenuItem: Hashable {
    case stat(Stat), claude(ClaudeWidget)

    /// Запись в настройках
    var key: String {
        switch self {
        case .stat(let s): return "stat.\(s.rawValue)"
        case .claude(let w): return "claude.\(w.rawValue)"
        }
    }

    init?(key: String) {
        if key.hasPrefix("stat."), let s = Stat(rawValue: String(key.dropFirst("stat.".count))) {
            self = .stat(s)
        } else if key.hasPrefix("claude."), let w = ClaudeWidget(rawValue: String(key.dropFirst("claude.".count))) {
            self = .claude(w)
        } else {
            return nil
        }
    }
}

/// Какие значки закреплены в строке меню и в каком порядке
final class StatsSettings: ObservableObject {
    /// В порядке закрепления: первый — крайний справа, каждый следующий встаёт левее
    @Published var menuOrder: [MenuItem] {
        didSet { UserDefaults.standard.set(menuOrder.map(\.key), forKey: DefaultsKey.menuOrder) }
    }
    var pinned: Set<Stat> {
        Set(menuOrder.compactMap { if case .stat(let s) = $0 { return s } else { return nil } })
    }
    var pinnedClaude: Set<ClaudeWidget> {
        Set(menuOrder.compactMap { if case .claude(let w) = $0 { return w } else { return nil } })
    }
    /// Тёмная «таблетка» под значками; без неё цвет значков — под светлую или тёмную строку меню
    @Published var menuPill = UserDefaults.standard.object(forKey: DefaultsKey.menuPill) as? Bool ?? false {
        didSet { UserDefaults.standard.set(menuPill, forKey: DefaultsKey.menuPill) }
    }
    /// Значок приложения, когда других наших значков нет; его меню — «Спрятать»
    @Published var showAppIcon = UserDefaults.standard.object(forKey: DefaultsKey.menuAppIcon) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showAppIcon, forKey: DefaultsKey.menuAppIcon) }
    }

    init() {
        let d = UserDefaults.standard
        if let saved = d.stringArray(forKey: DefaultsKey.menuOrder) {
            menuOrder = saved.compactMap(MenuItem.init(key:))
        } else if d.stringArray(forKey: DefaultsKey.menuStats) == nil && d.stringArray(forKey: DefaultsKey.menuClaude) == nil {
            // первый запуск: справа батарея, левее диск и сеть. Все пять значков на строке меню
            // MacBook рядом с чужими не помещаются, и macOS прячет лишние. Остальное включается булавкой
            menuOrder = [.stat(.battery), .stat(.disk), .stat(.network)]
        } else {
            // до порядка были два набора и значки шли в постоянном порядке: справа лимиты Claude,
            // левее статистики
            let stats = d.stringArray(forKey: DefaultsKey.menuStats).map { $0.compactMap(Stat.init(rawValue:)) } ?? [.cpu, .disk]
            let claude = (d.stringArray(forKey: DefaultsKey.menuClaude) ?? []).compactMap(ClaudeWidget.init(rawValue:))
            menuOrder = ClaudeWidget.allCases.reversed().filter(claude.contains).map(MenuItem.claude)
                + Stat.allCases.reversed().filter(stats.contains).map(MenuItem.stat)
        }
    }

    func toggle(_ s: Stat) { toggle(.stat(s)) }
    func toggle(_ w: ClaudeWidget) { toggle(.claude(w)) }

    /// Убрать или поставить последним — левее всех уже закреплённых
    func toggle(_ item: MenuItem) {
        if let i = menuOrder.firstIndex(of: item) { menuOrder.remove(at: i) } else { menuOrder.append(item) }
    }
}
