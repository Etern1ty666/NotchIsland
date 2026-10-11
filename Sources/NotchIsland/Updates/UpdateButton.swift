import SwiftUI

/// Зелёная кнопка внизу острова: «Доступно обновление»
struct UpdateButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("Доступно обновление")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(Capsule().fill(Theme.ok.opacity(hover ? 1 : 0.9)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Поставить новую версию — приложение перезапустится")
        .accessibilityLabel("Доступно обновление")
    }
}
