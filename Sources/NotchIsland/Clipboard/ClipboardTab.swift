import SwiftUI

/// Вкладка «Буфер»: вся история, новые сверху. Пустой буфер показывает подсказки
struct ClipboardTab: View {
    @ObservedObject var clip: ClipboardStore
    /// Остров раскрыт — при каждом раскрытии сбрасываем «Скопировано»
    let expanded: Bool

    @State private var copiedKey: String?

    var body: some View {
        FadingScrollView {
            if clip.items.isEmpty {
                ClipTips(retention: clip.retention)
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

    /// Ряды по две записи; непарная последняя растягивается — полупустых рядов не бывает
    func clipRows(_ items: [ClipItem]) -> [[ClipItem]] {
        stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }

    /// Ряд с картинкой выше: в нём видно сам снимок, а текст рядом — на несколько строк.
    /// Ряды ленивые: картинки грузятся, только когда до них долистали
    func clipGrid(_ items: [ClipItem]) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(clipRows(items), id: \.first!.id) { row in
                let tall = row.contains(where: \.isVisual)
                HStack(spacing: 8) {
                    ForEach(row) { item in
                        ClipCard(item: item,
                                 copied: copiedKey == item.id.uuidString,
                                 tall: tall,
                                 onCopy: {
                                     clip.copy(item)
                                     markCopied(item.id.uuidString)
                                 },
                                 onDelete: { withAnimation(.easeOut(duration: 0.2)) { clip.remove(item) } },
                                 onDrag: { clip.dragProvider(item) })
                    }
                }
                .frame(height: tall ? 96 : 44)
            }
        }
    }
}
