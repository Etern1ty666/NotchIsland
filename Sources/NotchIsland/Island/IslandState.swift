import SwiftUI

final class IslandState: ObservableObject {
    @Published var expanded = false
    /// Курсор лежит на вырезе и остров вот-вот раскроется — он немного «подрастает»
    @Published var peeking = false
    /// Остров всегда открывается на буфере
    @Published var tab: Tab = .clipboard
    /// Размер выреза (или его имитации на экране без выреза)
    @Published var notch = CGSize(width: 180, height: 32)
    /// Открыта страница настроек (шестерёнка справа от zzz) — вместо вкладки
    @Published var showSettings = false
    /// К какой строке прокрутить открывшиеся настройки (например, `SettingsView.claudeAccount`); nil — с начала
    @Published var settingsAnchor: String?
    /// После установки и каждого обновления вокруг выреза пульсирует зелёное свечение — «курсор сюда».
    /// Гаснет, когда остров раскроют
    @Published var showHint = UserDefaults.standard.string(forKey: DefaultsKey.islandHintVersion) != Updater.currentVersion
    /// Есть обновление или оно ставится — внизу острова полоса с кнопкой и прогрессом
    @Published var updateBar = false
    /// Показать меню «не засыпать» под кнопкой (её рамка в координатах острова)
    var openAwakeMenu: ((CGRect) -> Void)?

    /// Высота раскрытого острова зависит от вкладки; что не влезло, прокручивается.
    /// Настройки открываются в высоте текущей вкладки: если бы остров уменьшился, курсор
    /// (например, на карточке Claude внизу) оказался бы снаружи и остров свернулся бы
    var expandedHeight: CGFloat {
        let tabHeight: CGFloat
        switch tab {
        case .clipboard: tabHeight = Metrics.clipboardHeight
        case .stats: tabHeight = Metrics.statsHeight
        }
        return tabHeight + (updateBar ? Metrics.updateBarHeight : 0)
    }

    /// Верхняя строка раскрытого острова: по высоте выреза, но не ниже кнопок
    var topBarHeight: CGFloat { max(notch.height, 32) }
}

enum Tab: String, CaseIterable {
    case clipboard, stats
    var title: String {
        switch self {
        case .clipboard: return L("Буфер")
        case .stats: return L("Статистика")
        }
    }
}
