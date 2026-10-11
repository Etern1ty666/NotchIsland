import SwiftUI
import AppKit

struct ImageBox: @unchecked Sendable {
    let image: NSImage?
    init(_ image: NSImage?) { self.image = image }
}

/// Превью картинки целиком (без обрезки), по краям — она же, размытая: снимок любой формы
/// заполняет карточку без пустых полей
struct Thumb: View {
    let url: URL
    @State private var img: NSImage?

    var body: some View {
        Color.white.opacity(0.07)
            .overlay {
                if let img {
                    Image(nsImage: img).resizable().scaledToFill().blur(radius: 14).opacity(0.5)
                }
            }
            .overlay {
                if let img { Image(nsImage: img).resizable().scaledToFit() }
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
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
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
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Запись буфера. Клик — скопировать, перетаскивание — в другое окно;
/// при наведении вместо времени — булавка, «показать в Finder» и крестик
struct ClipCard: View {
    let item: ClipItem
    let copied: Bool
    /// Ряд с картинкой выше — текст в нём показывает больше строк
    let tall: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onDrag: () -> NSItemProvider
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let url = item.imageURL { visual(url) } else { plain }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .image: return "Картинка"
        case .screenshot: return item.text
        case .files: return item.urls.map(\.path).joined(separator: "\n")
        }
    }

    var showActions: Bool { hover && !copied }

    @ViewBuilder func actions(onImage: Bool) -> some View {
        HStack(spacing: 4) {
            ClipActionButton(systemName: item.pinned ? "pin.slash.fill" : "pin.fill",
                             help: item.pinned ? "Открепить" : "Закрепить — не удалится", onImage: onImage, action: onPin)
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

    /// Время; у закреплённой записи — с булавкой
    var timeLabel: some View {
        HStack(spacing: 3) {
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
            Text(relativeTime(item.date)).font(.system(size: 10).monospacedDigit())
        }
        .fixedSize()
    }

    // Текст, ссылка или файлы
    var plain: some View {
        HStack(spacing: 8) {
            icon.frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview)
                    .font(.system(size: 12))
                    .lineLimit(item.kind == .files ? 1 : (tall ? 5 : 2))
                    .truncationMode(item.kind == .files ? .middle : .tail)
                    .multilineTextAlignment(.leading)
                if item.kind == .files && item.urls.count > 1 {
                    Text("\(item.urls.count) \(plural(item.urls.count, "файл", "файла", "файлов"))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            timeLabel
                .foregroundStyle(Color.white.opacity(0.4))
                .opacity(hover || copied ? 0 : 1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardColor)
        // кнопки и «Скопировано» — поверх конца текста, а не в зарезервированном под них месте:
        // так тексту остаётся вся ширина карточки
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                Text("Скопировано")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .fixedSize()
                    .opacity(copied ? 1 : 0)
                actions(onImage: false)
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

    @ViewBuilder var icon: some View {
        if copied {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.green)
        } else if item.kind == .files, let url = item.urls.first {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: item.isLink ? "link" : "text.alignleft")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(item.isLink ? Theme.link : Color.white.opacity(0.45))
        }
    }

    // Картинка, скриншот или файл-картинка
    func visual(_ url: URL) -> some View {
        Thumb(url: url)
            .overlay(alignment: .bottom) {
                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        if item.kind == .screenshot { Image(systemName: "camera.viewfinder").font(.system(size: 9, weight: .bold)) }
                        timeLabel
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    Spacer(minLength: 0)
                    actions(onImage: true)
                }
                .padding(5)
            }
            .overlay {
                if copied {
                    ZStack {
                        Color.black.opacity(0.55)
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 22))
                            Text("Скопировано").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.green)
                    }
                }
            }
    }
}
