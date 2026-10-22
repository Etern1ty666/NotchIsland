import SwiftUI

/// Вкладка «Буфер»: вся история, новые первыми; под ней — подсказки (их можно спрятать).
/// Если macOS не даёт читать папку со скриншотами — сверху полоска с кнопкой «Разрешить».
/// После удаления внизу на несколько секунд — плашка «Вернуть»
struct ClipboardTab: View {
    @ObservedObject var clip: ClipboardStore
    /// Остров раскрыт — при каждом раскрытии сбрасываем «Скопировано»
    let expanded: Bool

    @State private var copiedKey: String?
    /// Время на записях («5 мин»): пересчитываем при раскрытии и раз в 15 с, пока остров открыт
    @State private var now = Date()

    var body: some View {
        Group {
            if clip.items.isEmpty && !clip.showTips && !clip.screenshotsDenied {
                emptyState
            } else {
                FadingScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if clip.screenshotsDenied { accessBanner }
                        if !clip.items.isEmpty { clipGrid(clip.items) }
                        // подсказки — внизу, под записями
                        if clip.showTips {
                            ClipTips { withAnimation(.easeOut(duration: 0.2)) { clip.showTips = false } }
                        }
                    }
                }
            }
        }
        // поверх стрелки «ниже есть ещё»: плашка важнее и скоро уйдёт
        .overlay(alignment: .bottom) {
            if let d = clip.deletion {
                UndoToast(text: d.all ? L("История очищена") : L("Запись удалена")) {
                    withAnimation(.easeOut(duration: 0.2)) { clip.undoDeletion() }
                }
                .id(d.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: clip.deletion)
        .onChange(of: expanded) { open in
            if open { copiedKey = nil }
        }
        .task(id: expanded) {
            guard expanded else { return }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    /// Пусто и подсказки спрятаны — одна строка, чтобы остров не казался сломанным
    var emptyState: some View {
        Label(L("Здесь появится всё скопированное"), systemImage: "doc.on.clipboard")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                         now: now,
                         onCopy: {
                             clip.copy(item)
                             markCopied(item.id.uuidString)
                         },
                         onDelete: { withAnimation(.easeOut(duration: 0.2)) { clip.delete([item]) } },
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

/// «Запись удалена · Вернуть» — внизу вкладки, пока удалённое ещё можно вернуть
struct UndoToast: View {
    let text: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
            Button(action: action) {
                Label(L("Вернуть"), systemImage: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(hover ? 1 : 0.88)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(Capsule().fill(Color(white: 0.17)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
    }
}
