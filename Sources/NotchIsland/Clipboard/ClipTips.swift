import SwiftUI

/// Подсказки под записями буфера — карточками, как в Gboard. «Спрятать» у заголовка убирает их
/// (вернуть — в настройках)
struct ClipTips: View {
    let onHide: () -> Void

    var tips: [(icon: String, text: String)] {
        [
            ("doc.on.clipboard", L("Всё скопированное — текст, ссылки, картинки и файлы — появляется здесь")),
            ("camera.viewfinder", L("Свежие скриншоты (⇧⌘3, ⇧⌘4) тоже попадают сюда")),
            ("cursorarrow.click", L("Клик по записи копирует её снова, ⌘-клик — выбирает несколько. Записи можно перетаскивать в другие окна")),
            ("clock.arrow.circlepath", L("История сохраняется после перезагрузки, срок хранения — в настройках")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionHeader(icon: "lightbulb", title: "Подсказки")
                HeaderButton(title: "Спрятать", help: "Вернуть подсказки можно в настройках", action: onHide)
            }
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
