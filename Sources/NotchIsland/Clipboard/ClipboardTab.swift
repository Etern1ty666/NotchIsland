import SwiftUI

/// Вкладка «Буфер»: закреплённые записи, недавние и подвал с паузой и очисткой.
/// Пустой буфер показывает подсказки
struct ClipboardTab: View {
    @ObservedObject var clip: ClipboardStore
    /// Остров раскрыт — при каждом раскрытии сбрасываем «Скопировано» и «Точно очистить?»
    let expanded: Bool
    let openSettings: () -> Void

    @State private var copiedKey: String?
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 8) {
            FadingScrollView {
                if clip.items.isEmpty {
                    ClipTips(retention: clip.retention)
                } else {
                    let pinned = clip.pinnedItems, recent = clip.recentItems
                    VStack(alignment: .leading, spacing: 8) {
                        // заголовки — только когда есть оба раздела
                        if !pinned.isEmpty {
                            SectionHeader(icon: "pin", title: "Закреплённые")
                            clipGrid(pinned)
                            if !recent.isEmpty {
                                SectionHeader(icon: "clock", title: "Недавние").padding(.top, 4)
                            }
                        }
                        clipGrid(recent)
                    }
                }
            }
            clipFooter
        }
        .onChange(of: expanded) { open in
            if open { copiedKey = nil; confirmClear = false }
        }
    }

    /// Пауза записи и срок хранения слева, очистка справа
    var clipFooter: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { clip.paused.toggle() }
            } label: {
                Label(clip.paused ? "Продолжить" : "Пауза", systemImage: clip.paused ? "play.fill" : "pause.fill")
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(Color.white.opacity(clip.paused ? 0.16 : 0.08)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.75))
            .help(clip.paused ? "Снова запоминать скопированное" : "Не запоминать новое, пока не включишь")
            Text(clip.paused ? "новое не запоминается" : clip.retention.hint)
                .foregroundStyle(clip.paused ? Theme.warning : Color.white.opacity(0.35))
                .onTapGesture(perform: openSettings)
                .help("Срок хранения — в настройках")
            Spacer()
            if !clip.recentItems.isEmpty {
                Button(confirmClear ? "Точно очистить?" : (clip.pinnedItems.isEmpty ? "Очистить всё" : "Очистить недавние")) {
                    if confirmClear {
                        withAnimation(.easeOut(duration: 0.2)) { clip.clear() }
                        confirmClear = false
                    } else {
                        confirmClear = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { confirmClear = false }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(confirmClear ? Color.red : Color.white.opacity(0.55))
                .help("Закреплённое останется")
            }
        }
        .font(.system(size: 11))
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

    /// Ряд с картинкой выше: в нём видно сам снимок, а текст рядом — на несколько строк
    func clipGrid(_ items: [ClipItem]) -> some View {
        VStack(spacing: 8) {
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
                                 onPin: { withAnimation(.easeOut(duration: 0.2)) { clip.togglePin(item) } },
                                 onDelete: { withAnimation(.easeOut(duration: 0.2)) { clip.remove(item) } },
                                 onDrag: { clip.dragProvider(item) })
                    }
                }
                .frame(height: tall ? 96 : 44)
            }
        }
    }
}
