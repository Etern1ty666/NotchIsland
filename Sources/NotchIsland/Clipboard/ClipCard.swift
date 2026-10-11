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

/// Запись буфера. Клик — скопировать, перетаскивание — в другое окно;
/// при наведении вместо времени — «показать в Finder» и крестик.
/// Размер — по содержимому: текст не шире, чем нужно (длинный переносится), снимок — по своей форме
struct ClipCard: View {
    /// Высота карточки со снимком; ширина — по пропорциям снимка, но в этих пределах
    static let visualHeight: CGFloat = 96
    /// Сверху — не шире 2,5 высоты: длинные снимки обрезаются по краям, а не тянутся на весь остров
    static let visualWidth: ClosedRange<CGFloat> = 60...240

    let item: ClipItem
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onDrag: () -> NSItemProvider
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let url = item.imageURL { visual(url) } else { plain }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(item.isVisual && hover ? 0.45 : 0), lineWidth: 1))
        .contentShape(shape)
        .onHover { hover = $0 }
        .onTapGesture(perform: onCopy)
        .onDrag(onDrag)
        .help(helpText)
        .animation(.easeOut(duration: 0.12), value: hover)
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
        Text(relativeTime(item.date)).font(.system(size: 10).monospacedDigit()).fixedSize()
    }

    // Текст, ссылка или файлы
    var plain: some View {
        HStack(spacing: 8) {
            if item.isLink {
                Image(systemName: "link")
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
            timeLabel
                .foregroundStyle(Color.white.opacity(0.4))
                .opacity(hover || copied ? 0 : 1)
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
        copied ? Color(red: 0.04, green: 0.16, blue: 0.07) : Color(white: hover ? 0.14 : 0.07)
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
                    .opacity(showActions && width < 150 ? 0 : 1)
            }
            .overlay(alignment: .bottomTrailing) {
                actions(onImage: true).padding(5)
            }
            .overlay {
                if copied {
                    ZStack {
                        Color.black.opacity(0.55)
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 22))
                            .foregroundStyle(Color.green)
                    }
                }
            }
    }
}
