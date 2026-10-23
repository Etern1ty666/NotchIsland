import SwiftUI

/// Цвета острова и строки меню. Остров всегда чёрный, поэтому полупрозрачный белый на нём —
/// это оттенки серого
enum Theme {
    /// Спокойно / заметно / под завязку — нагрузка, лимиты, состояния
    static let ok = Color(red: 0.32, green: 0.86, blue: 0.47)
    static let warning = Color(red: 1.0, green: 0.74, blue: 0.2)
    static let critical = Color(red: 1.0, green: 0.36, blue: 0.32)
    /// Опасные действия и ошибки: «Отключить», «Отмена», предупреждения в настройках
    static let danger = Color(red: 1, green: 0.45, blue: 0.4)
    static let link = Color(red: 0.45, green: 0.7, blue: 1)
    /// Выбранное ⌘-кликом в буфере: рамка, номер и плашка с действиями. Синий не берём у системы:
    /// графитовый акцент на чёрном острове почти не виден
    static let selection = Color(red: 0.2, green: 0.55, blue: 1)
    /// Включён режим «Держать экран включенным»
    static let awake = Color.orange
    /// Подложка карточек и строк
    static let card = Color.white.opacity(0.07)
    /// Карточка без данных (нет входа или ещё не загрузилось)
    static let idle = Color.white.opacity(0.45)
    /// Оттенок «таблеток» в строке меню (поверх размытия): тёмный, одинаково читается на светлой и тёмной строке меню
    static let menuBarPill = Color(white: 0.11)
}

extension View {
    /// Скруглённая подложка карточки
    func cardBackground(_ color: Color = Theme.card) -> some View {
        background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color))
    }
}

/// Цвет по уровню нагрузки: спокойно / заметно / под завязку
func loadColor(_ u: Double, calm: Double = 0.5, busy: Double = 0.8) -> Color {
    if u < calm { return Theme.ok }
    if u < busy { return Theme.warning }
    return Theme.critical
}

/// «37%» — число крупно, знак процента мельче и тусклее; при высокой нагрузке число краснеет.
/// `color` задаёт цвет числа явно, `ink` — основной цвет (белый на острове, в строке меню — под неё)
func percentText(_ u: Double, size: CGFloat, warn: Bool = true, color: Color? = nil, ink: Color = .white) -> Text {
    let number = Text("\(Int((u * 100).rounded()))")
        .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundColor(color ?? (warn && u >= 0.8 ? loadColor(u) : ink))
    let sign = Text("%")
        .font(.system(size: size * 0.75, weight: .semibold, design: .rounded))
        .foregroundColor(ink.opacity(0.5))
    return Text("\(number)\(sign)")
}

/// Крупное значение с подписью помельче и потусклее: «13,3 ГБ из 16,0 ГБ»
func valueText(_ big: String, _ small: String = "") -> Text {
    let b = Text(big).font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
    let s = Text(small).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.45))
    return Text("\(b)\(s)")
}
