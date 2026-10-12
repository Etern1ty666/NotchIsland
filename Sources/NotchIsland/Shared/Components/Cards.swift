import SwiftUI

struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Text(L(title))
            Image(systemName: icon)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.45))
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Общий вид карточки: значок и заголовок, крупное значение, шкала, строка подробностей.
/// Нажатие на карточку — подробности; булавка в углу — показывать ли её значок в строке меню
struct CardLayout<Value: View>: View {
    let icon: String
    let title: String
    let color: Color
    let gauge: Gauge
    let detail: String
    let pinned: Bool
    let onPin: () -> Void
    /// Подробности (меню как у значка в строке меню) или, если данных нет, настройки
    let onTap: () -> Void
    @ViewBuilder let value: () -> Value
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 0)
                PinButton(pinned: pinned, action: onPin)
                    // кружок крупнее строки заголовка — карточка от него не растёт
                    .padding(.vertical, -4)
                    .padding(.trailing, -3)
            }
            value()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GaugeView(gauge: gauge, color: color)
                .frame(height: gauge.isBar ? 6 : 18)
                .frame(height: 18)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(Color.white.opacity(hover ? 0.1 : 0.07))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
        .help(detail + "\n" + L("Нажатие — подробности"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: pinned ? L("Убрать из строки меню") : L("Показывать в строке меню"), onPin)
        .animation(.easeOut(duration: 0.3), value: color)
    }
}

/// Булавка карточки: показывать ли её значок в строке меню. Всегда в кружке — видно, что это кнопка;
/// закреплённая — белая заливка с тёмной булавкой, заметна издалека
struct PinButton: View {
    let pinned: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .bold))
                .rotationEffect(.degrees(45))
                .foregroundStyle(pinned ? Color.black : Color.white.opacity(hover ? 1 : 0.75))
                .frame(width: 22, height: 22)
                .background(Circle().fill(pinned ? Color.white.opacity(hover ? 0.8 : 0.95)
                                                 : Color.white.opacity(hover ? 0.22 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(pinned ? L("Показывается в строке меню. Нажатие — убрать") : L("Показывать в строке меню"))
        .animation(.easeOut(duration: 0.15), value: pinned)
    }
}
