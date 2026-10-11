import SwiftUI

/// Значок «сон»: zzz, перечёркнутый, когда Mac не даём засыпать.
/// Своего «zzz.slash» в SF Symbols нет — черту рисуем сами; под ней полоска цвета фона,
/// чтобы черта читалась поверх букв
struct SleepIcon: View {
    let slashed: Bool
    var size: CGFloat = 12
    /// Цвет подложки под значком — им «прорезаем» буквы вдоль черты
    var background: Color

    var body: some View {
        Image(systemName: "zzz")
            .font(.system(size: size, weight: .semibold))
            .overlay {
                if slashed {
                    ZStack {
                        Capsule().fill(background).frame(width: size * 0.24, height: size * 1.4)
                        Capsule().frame(width: size * 0.1, height: size * 1.3)
                    }
                    .rotationEffect(.degrees(-45))
                }
            }
    }
}

/// Круглая кнопка «не засыпать» с подсветкой при наведении
struct SleepButton: View {
    let slashed: Bool
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        // подложка — белый поверх чёрного острова; тот же цвет нужен значку для «прорези»
        let bg = Color(white: hover ? 0.16 : 0.08)
        Button(action: action) {
            SleepIcon(slashed: slashed, background: bg)
                .foregroundStyle(Color.white.opacity(hover ? 0.95 : 0.7))
                .frame(width: 26, height: 26)
                .background(Circle().fill(bg))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
