import SwiftUI

/// Полоса внизу острова: «Доступно обновление», затем прогресс скачивания и установки
struct UpdateBar: View {
    @ObservedObject var updater: Updater

    var body: some View {
        switch updater.phase {
        case .available, .ready:
            GreenButton(icon: "arrow.down.circle.fill", title: "Доступно обновление",
                        help: "Поставить новую версию — приложение перезапустится") { updater.update() }
        case .downloading(let p):
            ProgressCapsule(title: "Скачиваю обновление", progress: p)
        case .extracting(let p):
            ProgressCapsule(title: "Распаковываю", progress: p)
        case .installing:
            ProgressCapsule(title: "Устанавливаю", progress: nil)
        case .failed(let message):
            GreenButton(icon: "arrow.clockwise.circle.fill", title: "Не удалось обновить — ещё раз",
                        help: message, color: Theme.warning) { updater.update() }
        default:
            EmptyView()
        }
    }
}

/// Статус обновлений в настройках, справа от «Версия …»
struct UpdateStatus: View {
    @ObservedObject var updater: Updater

    var body: some View {
        switch updater.phase {
        case .idle:
            PillButton(title: "Проверить обновления") { updater.checkForUpdates() }
        case .checking:
            busy("Проверяю")
        case .upToDate:
            Label(L("Последняя версия"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ok)
        case .available(let v), .ready(let v):
            PillButton(title: L("Обновить до %@", v)) { updater.update() }
        case .downloading(let p):
            HStack(spacing: 8) {
                ProgressBar(progress: p).frame(width: 110, height: 6)
                Text(p.map { "\(Int(($0 * 100).rounded()))%" } ?? L("Скачиваю"))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        case .extracting:
            busy("Распаковываю")
        case .installing:
            busy("Устанавливаю")
        case .failed(let message):
            HStack(spacing: 8) {
                Text(L("Не удалось")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.danger)
                    .help(message)
                PillButton(title: "Ещё раз") { updater.update() }
            }
        }
    }

    func busy(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
            Text(L(text)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7))
        }
    }
}

/// Зелёная «таблетка»-кнопка внизу острова
struct GreenButton: View {
    let icon: String
    let title: String
    let help: String
    var color = Theme.ok
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(L(title)).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(Capsule().fill(color.opacity(hover ? 1 : 0.9)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L(help))
        .accessibilityLabel(L(title))
    }
}

/// «Скачиваю обновление · 45%» — капсула заполняется зелёным по мере загрузки
struct ProgressCapsule: View {
    let title: String
    /// nil — сколько осталось, неизвестно: капсула мягко пульсирует
    let progress: Double?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Text(L(title))
            if let progress { Text("\(Int((progress * 100).rounded()))%").monospacedDigit() }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16)
        .frame(minWidth: 220)
        .frame(height: 26)
        .background {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Theme.ok.opacity(progress == nil ? (pulse ? 0.55 : 0.25) : 0.55))
                        .frame(width: progress.map { max(g.size.height, g.size.width * $0) } ?? g.size.width)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}

/// Тонкая полоска прогресса; без значения — бегущий отрезок
struct ProgressBar: View {
    let progress: Double?

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(Theme.ok)
                    .frame(width: max(g.size.height, g.size.width * (progress ?? 0.3)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}
