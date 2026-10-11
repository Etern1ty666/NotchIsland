import Foundation
import UniformTypeIdentifiers

/// Что лежит в записи: всё, что можно скопировать, и свежие скриншоты из папки
enum ClipKind: String, Codable {
    case text, image, files, screenshot
}

/// Сколько хранить незакреплённое. По умолчанию час — как в буфере Gboard
enum ClipRetention: Int, CaseIterable, Identifiable {
    case hour = 3600, day = 86400, forever = 0
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .hour: return "1 час"
        case .day: return "1 день"
        case .forever: return "Всегда"
        }
    }
    /// Подпись в подвале буфера
    var hint: String {
        switch self {
        case .hour: return "незакреплённое удаляется через час"
        case .day: return "незакреплённое удаляется через сутки"
        case .forever: return "хранятся последние \(ClipboardStore.limit) незакреплённых"
        }
    }
}

struct ClipItem: Identifiable, Equatable, Codable {
    var id = UUID()
    let kind: ClipKind
    /// Сам текст; у файлов — их имена, у скриншота — имя файла
    let text: String
    /// Картинка из буфера — её копия в папке истории; файлы и скриншот — где они лежат
    let urls: [URL]
    var date: Date
    var pinned = false
    /// По нему узнаём повторное копирование того же самого (у текста — сам текст)
    let key: String
    /// Превью для списка: переносы и лишние пробелы схлопнуты, считаем один раз
    private(set) var preview = ""
    private(set) var isLink = false

    enum CodingKeys: String, CodingKey { case id, kind, text, urls, date, pinned, key }

    init(kind: ClipKind, text: String, urls: [URL] = [], date: Date = Date(), key: String = "") {
        self.kind = kind
        self.text = text
        self.urls = urls
        self.date = date
        self.key = key
        preview = text.prefix(400).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        isLink = kind == .text && Self.looksLikeLink(text)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try c.decode(ClipKind.self, forKey: .kind),
                  text: try c.decode(String.self, forKey: .text),
                  urls: try c.decode([URL].self, forKey: .urls),
                  date: try c.decode(Date.self, forKey: .date),
                  key: try c.decode(String.self, forKey: .key))
        id = try c.decode(UUID.self, forKey: .id)
        pinned = try c.decode(Bool.self, forKey: .pinned)
    }

    static func looksLikeLink(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(where: \.isWhitespace)
    }

    var identity: String { kind == .text ? text : key }

    /// Что показать картинкой: копию из буфера, скриншот или единственный файл-картинку
    var imageURL: URL? {
        switch kind {
        case .image, .screenshot: return urls.first
        case .files:
            guard urls.count == 1, let t = UTType(filenameExtension: urls[0].pathExtension) else { return nil }
            return t.conforms(to: .image) ? urls[0] : nil
        case .text: return nil
        }
    }
    var isVisual: Bool { imageURL != nil }
}
