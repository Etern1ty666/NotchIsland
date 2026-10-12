import SwiftUI

enum Metrics {
    /// «Тело» раскрытого острова (без ушек сверху)
    static let expanded = CGSize(width: 640, height: 280)
    /// Высота зависит от вкладки: в буфере ровно три ряда текста (или ряд с картинкой и два ряда текста),
    /// в статистике целиком видна «Система» и выглядывает верх карточек Claude — видно, что ниже есть ещё
    static let clipboardHeight: CGFloat = 280
    static let statsHeight: CGFloat = 372
    /// Полоса с зелёной кнопкой «Обновить» внизу — остров на неё подрастает, вкладки не сжимаются
    static let updateBarHeight: CGFloat = 38
    static let maxHeight = max(expanded.height, clipboardHeight, statsHeight) + updateBarHeight
    /// Вогнутые скругления сверху, которыми раскрытый остров переходит в край экрана
    static let flareExpanded: CGFloat = 10
    static let flarePeek: CGFloat = 6
    /// Насколько остров «подрастает», пока курсор ждёт на вырезе
    static let peek = CGSize(width: 12, height: 3)
    /// Спрятанный остров (вырез не используется): курсор у края — сразу выскакивает язычок такой высоты
    static let hiddenPeekHeight: CGFloat = 10
    static let hiddenPeekPop = Animation.spring(response: 0.2, dampingFraction: 0.8)
    /// Прозрачный запас вокруг раскрытого острова: под тень и «пружину» анимации
    static let margin = CGSize(width: 24, height: 32)

    /// Сколько курсор должен пробыть на вырезе, чтобы остров раскрылся
    static let hoverDelay: TimeInterval = 0.5
    /// Пауза перед сворачиванием, когда курсор ушёл: прощает случайный промах мимо края
    static let leaveDelay: TimeInterval = 0.25

    /// Раскрытие — с лёгкой пружиной
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.82)
    /// Сворачивание — без перелёта: пружина «проскакивала» меньше выреза и отскакивала обратно,
    /// и в конце остров неровно дёргался
    static let collapse = Animation.spring(response: 0.32, dampingFraction: 1)
}
