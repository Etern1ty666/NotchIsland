import SwiftUI
import AppKit

struct ImageBox: @unchecked Sendable {
    let image: NSImage?
    init(_ image: NSImage?) { self.image = image }
}

/// Превью снимка на всю карточку. Карточка по форме снимка, так что он виден целиком;
/// подрезаются только совсем узкие и сверхширокие, чью форму пришлось ограничить
struct Thumb: View {
    let url: URL
    @State private var img: NSImage?

    var body: some View {
        Color.white.opacity(0.07)
            .overlay {
                if let img { Image(nsImage: img).resizable().scaledToFill() }
            }
            .clipped()
            .task(id: url) {
                img = await Task.detached { ImageBox(Thumb.load(url)) }.value.image
            }
    }

    nonisolated static func load(_ url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }

    /// Ширина к высоте снимка — из заголовка файла, без загрузки самой картинки; запоминаем
    @MainActor private static var aspects: [URL: CGFloat] = [:]

    @MainActor static func aspect(_ url: URL) -> CGFloat {
        if let a = aspects[url] { return a }
        var a: CGFloat = 16.0 / 10
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0 {
            // поворот из EXIF (5–8) меняет стороны местами
            let rotated = ((p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) >= 5
            a = rotated ? h / w : w / h
        }
        aspects[url] = a
        return a
    }
}

/// Маленькая круглая кнопка на карточке записи
struct ClipActionButton: View {
    let systemName: String
    let help: String
    var onImage = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(hover ? 1 : 0.8))
                .frame(width: 22, height: 22)
                .background(Circle().fill(onImage ? Color.black.opacity(hover ? 0.85 : 0.65)
                                                  : Color.white.opacity(hover ? 0.24 : 0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L(help))
        .accessibilityLabel(L(help))
    }
}

/// Запись буфера. Клик — скопировать, ⌘-клик — выбрать (синяя рамка и номер), перетаскивание — в другое окно;
/// при наведении вместо времени — «показать в Finder» и крестик.
/// Размер — по содержимому: текст не шире, чем нужно (длинный переносится), снимок — по своей форме
struct ClipCard: View {
    /// Высота карточки со снимком; ширина — по пропорциям снимка, но в этих пределах
    static let visualHeight: CGFloat = 96
    /// Сверху — не шире 2,5 высоты: длинные снимки обрезаются по краям, а не тянутся на весь остров
    static let visualWidth: ClosedRange<CGFloat> = 60...240

    let item: ClipItem
    let copied: Bool
    /// Место в выборе (⌘-клик), с единицы: в таком порядке выбранные и скопируются. nil — не выбрана
    let selection: Int?
    /// Не подходит к выбранным (текст к файлам и наоборот): серая, ⌘-клик её не выбирает
    let dimmed: Bool
    /// Сейчас — от него «5 мин» на записи; меняется, пока остров открыт
    let now: Date
    /// Клик: скопировать или, с ⌘, выбрать — решает вкладка
    let onTap: () -> Void
    let onDelete: () -> Void
    let onDrag: () -> NSItemProvider
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let url = item.imageURL { visual(url) } else { plain }
        }
        .clipShape(shape)
        .overlay {
            if selected {
                // на картинке рамку отделяет от снимка тёмная линия: иначе на синем она теряется
                ZStack {
                    if item.isVisual { shape.inset(by: 2).strokeBorder(Color.black.opacity(0.7), lineWidth: 1.5) }
                    shape.strokeBorder(Theme.selection, lineWidth: 2)
                }
            } else {
                shape.strokeBorder(Color.white.opacity(item.isVisual && hover ? 0.45 : 0), lineWidth: 1)
            }
        }
        .saturation(dimmed ? 0 : 1)
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(shape)
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
        .onDrag(onDrag)
        .help(dimmed ? L("Текст и файлы вместе не вставить — эту запись не выбрать вместе с выбранными") : helpText)
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.12), value: selection)
        .animation(.easeOut(duration: 0.15), value: dimmed)
    }

    var selected: Bool { selection != nil && !copied }

    /// Номер в выборе — белым на синем кружке
    func selectionBadge(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.white)
            .padding(.horizontal, n > 9 ? 4 : 0)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Theme.selection))
            .fixedSize()
    }

    var helpText: String {
        switch item.kind {
        case .text: return String(item.text.prefix(500))
        case .image: return L("Картинка")
        case .screenshot: return item.text
        case .files: return item.urls.map(\.path).joined(separator: "\n")
        }
    }

    var showActions: Bool { hover && !copied }

    @ViewBuilder func actions(onImage: Bool) -> some View {
        HStack(spacing: 4) {
            if item.kind == .files || item.kind == .screenshot {
                ClipActionButton(systemName: "folder", help: "Показать в Finder", onImage: onImage) {
                    NSWorkspace.shared.activateFileViewerSelecting(item.urls)
                }
            }
            ClipActionButton(systemName: "xmark", help: "Удалить из истории", onImage: onImage, action: onDelete)
        }
        .opacity(showActions ? 1 : 0)
        .allowsHitTesting(showActions)
    }

    /// Когда скопировали
    var timeLabel: some View {
        Text(relativeTime(item.date, now: now)).font(.system(size: 10).monospacedDigit()).fixedSize()
    }

    // Текст, ссылка или файлы
    var plain: some View {
        HStack(spacing: 8) {
            // ссылка — цепочка, файлы — лист (несколько — стопка)
            if item.isLink || item.kind == .files {
                Image(systemName: item.isLink ? "link" : (item.urls.count > 1 ? "doc.on.doc" : "doc"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview)
                    .font(.system(size: 12))
                    .lineLimit(item.kind == .files ? 1 : 4)
                    .truncationMode(item.kind == .files ? .middle : .tail)
                    .multilineTextAlignment(.leading)
                if item.kind == .files && item.urls.count > 1 {
                    Text(countText(item.urls.count, ru: ("файл", "файла", "файлов"), en: ("file", "files")))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            // номер встаёт на место времени: ширина карточки не меняется, соседи не прыгают
            timeLabel
                .foregroundStyle(Color.white.opacity(0.4))
                .opacity(hover || copied || selected ? 0 : 1)
                .overlay(alignment: .trailing) {
                    if let selection, selected { selectionBadge(selection).opacity(hover ? 0 : 1) }
                }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        // не уже, чем нужно кнопкам при наведении, и не ниже одной строки с запасом
        .frame(minWidth: 100, minHeight: 44, alignment: .leading)
        .background(cardColor)
        // кнопки и «Скопировано» — поверх конца текста, а не в зарезервированном под них месте:
        // так тексту остаётся вся ширина карточки
        .overlay(alignment: .trailing) {
            // подложка ровно под то, что видно: в короткой карточке не закрывает текст целиком
            Group {
                if copied {
                    Text(L("Скопировано"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .fixedSize()
                } else {
                    actions(onImage: false)
                }
            }
            .padding(.leading, 24)
            .padding(.trailing, 8)
            .frame(maxHeight: .infinity)
            .background(LinearGradient(stops: [.init(color: cardColor.opacity(0), location: 0),
                                               .init(color: cardColor, location: 0.25)],
                                       startPoint: .leading, endPoint: .trailing))
            .opacity(hover || copied ? 1 : 0)
        }
    }

    /// Непрозрачный цвет карточки (остров чёрный): им же подложены кнопки поверх текста
    var cardColor: Color {
        if copied { return Color(red: 0.04, green: 0.16, blue: 0.07) }
        if selected { return hover ? Color(red: 0.09, green: 0.2, blue: 0.36) : Color(red: 0.06, green: 0.15, blue: 0.29) }
        return Color(white: hover ? 0.14 : 0.07)
    }

    /// «✓ Скопировано» поверх картинки — на тёмной подложке, чтобы читалось и на светлом снимке.
    /// Узкой карточке не хватает ширины на строку — значок над словом
    var copiedBadge: some View {
        let icon = Image(systemName: "checkmark.circle.fill")
        let text = Text(L("Скопировано")).lineLimit(1)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                icon.font(.system(size: 12, weight: .semibold))
                text.font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            // узкая — затемнена сильнее целиком: ширина вся под слово
            VStack(spacing: 4) {
                icon.font(.system(size: 18, weight: .semibold))
                // сжатое начертание: «Скопировано» помещается в самую узкую карточку без мелкого кегля
                text.font(.system(size: 10, weight: .semibold).width(.condensed)).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.4))
        }
        .foregroundStyle(Color.green)
    }

    // Картинка, скриншот или файл-картинка
    func visual(_ url: URL) -> some View {
        let width = min(max(Self.visualHeight * Thumb.aspect(url), Self.visualWidth.lowerBound),
                        Self.visualWidth.upperBound)
        return Thumb(url: url)
            .frame(width: width, height: Self.visualHeight)
            // время и кнопки — каждое в своём углу; в узкой карточке при наведении время уступает место
            .overlay(alignment: .bottomLeading) {
                timeLabel
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(5)
                    .opacity(copied || (showActions && width < 150) ? 0 : 1)
            }
            .overlay(alignment: .bottomTrailing) {
                actions(onImage: true).padding(5)
            }
            .overlay(alignment: .topLeading) {
                if let selection, selected { selectionBadge(selection).padding(5) }
            }
            .overlay {
                if copied {
                    ZStack {
                        Color.black.opacity(0.45)
                        copiedBadge
                    }
                }
            }
    }
}
