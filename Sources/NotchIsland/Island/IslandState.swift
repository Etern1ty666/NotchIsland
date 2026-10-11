import SwiftUI

final class IslandState: ObservableObject {
    @Published var expanded = false
    /// Курсор лежит на вырезе и остров вот-вот раскроется — он немного «подрастает»
    @Published var peeking = false
    /// Последняя открытая вкладка запоминается между запусками
    @Published var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.lastTab) ?? "") ?? .clipboard {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: DefaultsKey.lastTab) }
    }
    /// Размер выреза (или его имитации на экране без выреза)
    @Published var notch = CGSize(width: 180, height: 32)
    /// Открыта страница настроек (кнопка справа от zzz) — вместо вкладки
    @Published var showSettings = false
    /// Показать меню «не засыпать» под кнопкой (её рамка в координатах острова)
    var openAwakeMenu: ((CGRect) -> Void)?

    /// Высота раскрытого острова зависит от вкладки; что не влезло, прокручивается.
    /// Настройки открываются в высоте текущей вкладки: если бы остров уменьшился, курсор
    /// (например, на карточке Claude внизу) оказался бы снаружи и остров свернулся бы
    var expandedHeight: CGFloat {
        switch tab {
        case .clipboard: return Metrics.clipboardHeight
        case .stats: return Metrics.statsHeight
        }
    }

    /// Верхняя строка раскрытого острова: по высоте выреза, но не ниже кнопок
    var topBarHeight: CGFloat { max(notch.height, 32) }
}

enum Tab: String, CaseIterable {
    case clipboard, stats
    var icon: String {
        switch self {
        case .clipboard: return "list.clipboard"
        case .stats: return "waveform.path.ecg"
        }
    }
    var title: String {
        switch self {
        case .clipboard: return "Буфер"
        case .stats: return "Статистика"
        }
    }
}
