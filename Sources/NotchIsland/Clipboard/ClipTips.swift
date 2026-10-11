import SwiftUI

/// Подсказки вместо пустого буфера — карточками, как в Gboard
struct ClipTips: View {
    var tips: [(icon: String, text: String)] {
        [
            ("doc.on.clipboard", "Всё, что копируешь, — текст, ссылки, картинки и файлы — появится здесь"),
            ("camera.viewfinder", "Свежие скриншоты (⇧⌘3, ⇧⌘4) тоже попадают сюда"),
            ("cursorarrow.click", "Клик по записи копирует её снова. Её можно и перетащить в другое окно"),
            ("clock.arrow.circlepath", "История остаётся после перезагрузки — можно изменить в настройках"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "lightbulb", title: "Подсказки")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(tips, id: \.icon) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: tip.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Self.accent)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Self.accent.opacity(0.18)))
                        Text(tip.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                    .cardBackground()
                }
            }
        }
    }

    static let accent = Color(red: 0.62, green: 0.66, blue: 1)
}
