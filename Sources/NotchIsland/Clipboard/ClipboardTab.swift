import SwiftUI

/// Вкладка «Буфер»: вся история, новые первыми; под ней — подсказки (их можно спрятать).
/// Если macOS не даёт читать папку со скриншотами — сверху полоска с кнопкой «Разрешить».
/// После удаления внизу на несколько секунд — плашка «Вернуть»; пока ⌘-кликом выбраны записи —
/// внизу сколько их, а действия с ними — вверху острова вместо вкладок
struct ClipboardTab: View {
    @ObservedObject var clip: ClipboardStore
    /// Остров раскрыт — при каждом раскрытии сбрасываем «Скопировано»
    let expanded: Bool

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
                        // последний ряд можно докрутить из-под надписи «выбрано»
                        if !clip.selection.isEmpty { Color.clear.frame(height: 24) }
                    }
                }
            }
        }
        // клик мимо записей снимает выбор (по записи — её собственный клик)
        .contentShape(Rectangle())
        .onTapGesture { clip.clearSelection() }
        // поверх стрелки «ниже есть ещё»: плашки важнее и скоро уйдут
        .overlay(alignment: .bottom) {
            VStack(spacing: 6) {
                if let d = clip.deletion {
                    UndoToast(text: undoText(d)) {
                        withAnimation(.easeOut(duration: 0.2)) { clip.undoDeletion() }
                    }
                    .id(d.id)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if !clip.selection.isEmpty {
                    SelectionCount(count: clip.selection.count)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: clip.deletion)
        .animation(.easeOut(duration: 0.15), value: clip.selection.isEmpty)
        .onChange(of: expanded) { open in
            if open { clip.clearCopiedMarks() }
        }
        // ушли на другую вкладку или в настройки — выбор не тянется за спиной
        .onDisappear { clip.clearSelection() }
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

    /// Записи потоком: каждая своего размера, текст не шире двух третей острова
    func clipGrid(_ items: [ClipItem]) -> some View {
        // первая выбранная решает, что ещё можно выбрать: остальные серые (см. ClipboardStore.canSelect)
        let textOnly = clip.selectionIsText
        return FlowLayout(spacing: 8, maxItemWidth: 400) {
            ForEach(items) { item in
                let index = clip.selection.firstIndex(of: item.id)
                ClipCard(item: item,
                         copied: clip.copied.contains(item.id),
                         selection: index.map { $0 + 1 },
                         dimmed: index == nil && textOnly.map { $0 != (item.kind == .text) } == true,
                         now: now,
                         onTap: { tap(item) },
                         onDelete: { withAnimation(.easeOut(duration: 0.2)) { clip.delete([item]) } },
                         onDrag: { clip.dragProvider(item) })
            }
        }
    }

    /// Клик копирует запись и снимает выбор; с ⌘ — добавляет запись к выбору или убирает из него
    func tap(_ item: ClipItem) {
        if NSEvent.modifierFlags.contains(.command) {
            clip.toggleSelection(item)
        } else {
            clip.clearSelection()
            clip.copy(item)
        }
    }

    func undoText(_ d: ClipboardStore.Deletion) -> String {
        if d.all { return L("История очищена") }
        if d.items.count == 1 { return L("Запись удалена") }
        return L("Удалено: %@", countText(d.items.count, ru: ("запись", "записи", "записей"), en: ("item", "items")))
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

/// «3 элемента выбрано» — внизу вкладки, пока ⌘-кликом выбраны записи. Что с ними сделать — вверху острова
struct SelectionCount: View {
    let count: Int

    var body: some View {
        Text(Self.text(count))
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Capsule().fill(Color(white: 0.17)))
            .overlay(Capsule().strokeBorder(Theme.selection.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
    }

    /// «1 элемент выбран», «3 элемента выбрано», «21 элемент выбран»
    static func text(_ n: Int) -> String {
        let noun = countText(n, ru: ("элемент", "элемента", "элементов"), en: ("item", "items"))
        return n % 10 == 1 && n % 100 != 11 ? L("%@ выбран", noun) : L("%@ выбрано", noun)
    }
}

/// Что сделать с выбранными — в верхней строке острова вместо вкладок и кнопок, пока выбор есть
/// (см. `IslandView.topBar`): слева от выреза «Скопировать» и «Показать в Finder», справа «Удалить»
/// и «Снять выбор». С клавиатуры то же самое: ⌘C, ⌫, Esc
struct SelectionActions: View {
    @ObservedObject var clip: ClipboardStore
    /// Левая половина строки (до выреза) или правая
    let leading: Bool

    var body: some View {
        HStack(spacing: 6) {
            if leading {
                SelectionButton(title: "Скопировать", icon: "doc.on.doc", filled: true,
                                help: "Скопировать вместе, по порядку номеров (⌘C)") { clip.copySelection() }
                let onDisk = filesOnDisk
                if !onDisk.isEmpty {
                    CircleIconButton(systemName: "folder", help: "Показать в Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(onDisk)
                    }
                }
            } else {
                SelectionButton(title: "Удалить", icon: "trash", filled: false, help: "Удалить выбранные (⌫)") {
                    withAnimation(.easeOut(duration: 0.2)) { clip.deleteSelection() }
                }
                CircleIconButton(systemName: "xmark", help: "Снять выбор (Esc)") { clip.clearSelection() }
            }
        }
    }

    /// В Finder — только то, что лежит на диске само по себе; копии картинок из буфера — наши, служебные
    var filesOnDisk: [URL] {
        clip.selectedItems.filter { $0.kind == .files || $0.kind == .screenshot }.flatMap(\.urls)
    }
}

/// Кнопка-«таблетка» со значком в верхней строке при выборе: «Скопировать» — синяя, «Удалить» — красным текстом
struct SelectionButton: View {
    let title: String
    let icon: String
    let filled: Bool
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(L(title), systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(filled ? Color.white : Theme.danger)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(filled ? Theme.selection.opacity(hover ? 1 : 0.85)
                                                  : Color.white.opacity(hover ? 0.16 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L(help))
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
