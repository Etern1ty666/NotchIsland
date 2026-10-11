import SwiftUI

/// Вкладка «Буфер»: вся история, новые первыми; под ней — подсказки.
/// Если macOS не даёт читать папку со скриншотами — сверху полоска с кнопкой «Разрешить»
struct ClipboardTab: View {
    @ObservedObject var clip: ClipboardStore
    /// Остров раскрыт — при каждом раскрытии сбрасываем «Скопировано»
    let expanded: Bool

    @State private var copiedKey: String?

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if clip.screenshotsDenied { accessBanner }
                if !clip.items.isEmpty { clipGrid(clip.items) }
                // подсказки — всегда внизу, под записями
                ClipTips()
            }
        }
        .onChange(of: expanded) { open in
            if open { copiedKey = nil }
        }
    }

    // MARK: Записи

    /// Остров после копирования не сворачивается — галочка на элементе гаснет сама
    func markCopied(_ key: String) {
        copiedKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedKey == key { copiedKey = nil }
        }
    }

    /// Записи потоком: каждая своего размера, текст не шире двух третей острова
    func clipGrid(_ items: [ClipItem]) -> some View {
        FlowLayout(spacing: 8, maxItemWidth: 400) {
            ForEach(items) { item in
                ClipCard(item: item,
                         copied: copiedKey == item.id.uuidString,
                         onCopy: {
                             clip.copy(item)
                             markCopied(item.id.uuidString)
                         },
                         onDelete: { withAnimation(.easeOut(duration: 0.2)) { clip.remove(item) } },
                         onDrag: { clip.dragProvider(item) })
            }
        }
    }

    /// Нет доступа к папке со скриншотами — кнопка снова вызывает окно macOS
    var accessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.warning)
            Text(L("Скриншоты не видны — нет доступа к папке «%@»", clip.screenshotFolderName))
                .font(.system(size: 12))
                .lineLimit(2)
            Spacer(minLength: 0)
            PillButton(title: "Разрешить") { clip.requestScreenshotAccess() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .cardBackground(Theme.warning.opacity(0.12))
    }
}
