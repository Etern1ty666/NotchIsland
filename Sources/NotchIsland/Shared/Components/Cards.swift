import SwiftUI

struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: icon)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.45))
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Общий вид карточки: значок и заголовок, крупное значение, шкала, строка подробностей
struct CardLayout<Value: View>: View {
    let icon: String
    let title: String
    let color: Color
    let gauge: Gauge
    let detail: String
    /// nil — карточку нельзя закрепить в строке меню; иначе клик по карточке закрепляет и открепляет
    var pinned: Bool? = nil
    var onPin: () -> Void = {}
    /// Свой клик по карточке (например, «нет входа — открыть настройки») — вместо закрепления
    var onTap: (() -> Void)? = nil
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
                if onTap == nil, let pinned {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(pinned ? Color.white : Color.white.opacity(hover ? 0.6 : 0.3))
                        .frame(width: 18, height: 18)
                } else if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(hover ? 0.6 : 0.3))
                        .frame(width: 18, height: 18)
                }
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
        .onTapGesture { if let onTap { onTap() } else if pinned != nil { onPin() } }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(pinHint ?? "")
        .animation(.easeOut(duration: 0.3), value: color)
    }

    private var pinHint: String? {
        guard onTap == nil, let pinned else { return nil }
        return pinned ? "Нажми, чтобы убрать из строки меню" : "Нажми, чтобы показывать в строке меню"
    }

    private var helpText: String {
        pinHint.map { detail + "\n" + $0 } ?? detail
    }
}
