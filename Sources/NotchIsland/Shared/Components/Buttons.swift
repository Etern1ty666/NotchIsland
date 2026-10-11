import SwiftUI

/// Круглая кнопка-значок в верхней строке; active — подсвечена (открыта её страница)
struct CircleIconButton: View {
    let systemName: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(active || hover ? 0.95 : 0.7))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(active ? 0.22 : (hover ? 0.16 : 0.08))))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L(help))
        .accessibilityLabel(L(help))
    }
}

/// Маленькая кнопка-«таблетка» для настроек
struct PillButton: View {
    let title: String
    var destructive = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(L(title))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(destructive ? Theme.danger : Color.white)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(hover ? 0.18 : 0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Маленькая кнопка «обновить»: закруглённая стрелка, при нажатии делает оборот
struct RefreshButton: View {
    let busy: Bool
    let action: () -> Void
    @State private var hover = false
    @State private var angle: Double = 0

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.6)) { angle += 360 }
            action()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(angle))
                .foregroundStyle(Color.white.opacity(busy ? 0.25 : (hover ? 0.8 : 0.4)))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(hover && !busy ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hover = $0 }
        .help(L("Обновить"))
        .accessibilityLabel(L("Обновить"))
    }
}

/// Переключатель-«таблетки»: несколько вариантов, выбран один
struct SegmentPicker<T: Hashable>: View {
    let options: [(value: T, title: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { o in
                SegmentButton(title: o.title, selected: o.value == selection) { selection = o.value }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

struct SegmentButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(L(title))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(selected ? 1 : (hover ? 0.85 : 0.55)))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.2 : (hover ? 0.08 : 0))))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
