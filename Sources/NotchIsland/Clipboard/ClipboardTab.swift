import SwiftUI

/// Вкладка «Буфер»: вся история, новые первыми. Пустой буфер показывает подсказки
struct ClipboardTab: View {
    @ObservedObject var clip: ClipboardStore
    /// Остров раскрыт — при каждом раскрытии сбрасываем «Скопировано»
    let expanded: Bool

    @State private var copiedKey: String?

    var body: some View {
        FadingScrollView {
            if clip.items.isEmpty {
                ClipTips()
            } else {
                clipGrid(clip.items)
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
}
