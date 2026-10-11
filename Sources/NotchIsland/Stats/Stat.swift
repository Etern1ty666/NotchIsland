import SwiftUI

/// Что умеем показывать: каждая статистика — отдельный значок в строке меню и карточка на острове
enum Stat: String, CaseIterable, Identifiable {
    case cpu, memory, network, disk, battery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: return "Процессор"
        case .memory: return "Память"
        case .network: return "Сеть"
        case .disk: return "Диск"
        case .battery: return "Батарея"
        }
    }
}

/// Какие статистики закреплены в строке меню
final class StatsSettings: ObservableObject {
    @Published var pinned: Set<Stat> {
        didSet { UserDefaults.standard.set(pinned.map(\.rawValue), forKey: DefaultsKey.menuStats) }
    }
    @Published var pinnedClaude: Set<ClaudeWidget> {
        didSet { UserDefaults.standard.set(pinnedClaude.map(\.rawValue), forKey: DefaultsKey.menuClaude) }
    }
    /// Значок приложения, когда других наших значков нет; его меню — «Спрятать»
    @Published var showAppIcon = UserDefaults.standard.object(forKey: DefaultsKey.menuAppIcon) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showAppIcon, forKey: DefaultsKey.menuAppIcon) }
    }

    init() {
        // по умолчанию — процессор и диск: все пять значков на строке меню MacBook рядом
        // с чужими не помещаются, и macOS прячет лишние. Остальное включается булавкой
        let saved = UserDefaults.standard.stringArray(forKey: DefaultsKey.menuStats)
        pinned = saved.map { Set($0.compactMap(Stat.init(rawValue:))) } ?? [.cpu, .disk]
        let savedClaude = UserDefaults.standard.stringArray(forKey: DefaultsKey.menuClaude) ?? []
        pinnedClaude = Set(savedClaude.compactMap(ClaudeWidget.init(rawValue:)))
    }

    func toggle(_ s: Stat) {
        if pinned.contains(s) { pinned.remove(s) } else { pinned.insert(s) }
    }

    func toggle(_ w: ClaudeWidget) {
        if pinnedClaude.contains(w) { pinnedClaude.remove(w) } else { pinnedClaude.insert(w) }
    }
}

struct BatteryInfo: Equatable {
    var level: Double        // 0...1
    var charging: Bool
    var onAC: Bool
    var minutesLeft: Int?    // до полной зарядки или до разряда
}
