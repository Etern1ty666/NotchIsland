import SwiftUI
import AppKit
import CryptoKit

/// История всего скопированного вместе со свежими скриншотами. Лежит на диске и переживает
/// перезапуск и перезагрузку; по умолчанию хранится всегда (срок — в настройках)
final class ClipboardStore: ObservableObject {
    /// Записей не больше стольких — дальше уходят самые старые
    static let limit = 100
    /// Не сохраняем то, что менеджеры паролей и другие приложения просят не запоминать
    private static let skippedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword",
    ]
    static let dir = AppPaths.support.appendingPathComponent("Clipboard", isDirectory: true)
    private static let file = dir.appendingPathComponent("history.json")

    /// Все записи, новые сверху
    @Published private(set) var items: [ClipItem] = []
    /// macOS не даёт читать папку со скриншотами (в окне доступа нажали «Не разрешать»)
    @Published private(set) var screenshotsDenied = false
    @Published var retention = ClipRetention(rawValue: UserDefaults.standard.object(forKey: DefaultsKey.clipRetention) as? Int
                                             ?? ClipRetention.forever.rawValue) ?? .forever {
        didSet {
            UserDefaults.standard.set(retention.rawValue, forKey: DefaultsKey.clipRetention)
            prune()
        }
    }

    private var lastCount = NSPasteboard.general.changeCount
    /// Скриншоты, которые уже побывали в ленте: удалённый из ленты не вернётся
    private var seenShots: [String] = []
    /// Диск — по очереди: запись истории, сохранение и удаление картинок
    private let io = DispatchQueue(label: "NotchIsland.clipboard")
    private var saveWork: DispatchWorkItem?
    private var timers: [Timer] = []

    init() {
        load()
        poll(force: true)
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.1
        // устаревшее убираем и пока остров закрыт
        let p = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.prune() }
        p.tolerance = 10
        for timer in [t, p] { RunLoop.main.add(timer, forMode: .common) }
        timers = [t, p]
    }

    // MARK: Что скопировали

    func poll(force: Bool = false) {
        let pb = NSPasteboard.general
        guard force || pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains(where: Self.skippedTypes.contains) { return }
        // при запуске в буфере то, что уже было: не поднимаем его наверх как новое
        let existing = force

        // файлы из Finder
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            add(ClipItem(kind: .files, text: urls.map(\.lastPathComponent).joined(separator: ", "), urls: urls,
                         key: "files:" + urls.map(\.path).joined(separator: "\n")), existing: existing)
            return
        }
        let s = pb.string(forType: .string)
        let hasText = s.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        // картинка — когда текста нет или это лишь её адрес («Скопировать изображение» в браузере).
        // Офисные программы кладут к тексту ещё и его картинку — там нужен текст
        if let type = pb.availableType(from: [.png, .tiff]), let data = pb.data(forType: type),
           !hasText || ClipItem.looksLikeLink(s ?? "") {
            addImage(data, isPNG: type == .png, existing: existing)
            return
        }
        if let s, hasText { add(ClipItem(kind: .text, text: s), existing: existing) }
    }

    /// Картинку храним копией в PNG — его понимают все приложения. Имя файла — хеш содержимого
    private func addImage(_ data: Data, isPNG: Bool, existing: Bool) {
        guard data.count < 50_000_000 else { return }
        let date = Date()
        io.async { [weak self] in
            guard let png = isPNG ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
            else { return }
            let hash = SHA256.hash(data: png).prefix(16).map { String(format: "%02x", $0) }.joined()
            let url = Self.dir.appendingPathComponent(hash + ".png")
            if !FileManager.default.fileExists(atPath: url.path) {
                Self.makeDir()
                guard (try? png.write(to: url, options: .atomic)) != nil else { return }
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            DispatchQueue.main.async {
                self?.add(ClipItem(kind: .image, text: "", urls: [url], date: date, key: "image:" + hash),
                          existing: existing)
            }
        }
    }

    /// Повтор того же самого поднимает запись наверх
    private func add(_ item: ClipItem, existing: Bool = false) {
        if let i = items.firstIndex(where: { $0.identity == item.identity }) {
            if existing { return }
            items.remove(at: i)
        }
        items.insert(item, at: items.firstIndex { $0.date < item.date } ?? items.count)
        prune()
        save()
    }

    // MARK: Скриншоты

    static func screenshotDir() -> URL {
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (loc as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Стандартные названия файлов + своё, если оно задано через `defaults write com.apple.screencapture name`
    static func screenshotPrefixes() -> [String] {
        var p = ["screenshot", "screen shot", "снимок экрана"]
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "name"), !custom.isEmpty {
            p.append(custom.lowercased())
        }
        return p
    }

    /// Новые скриншоты из папки — в ленту (при раскрытии острова). true — есть совсем свежий
    @discardableResult
    func scanScreenshots() -> Bool {
        // удалённые с диска убираем и из ленты
        remove(items.filter { $0.kind == .screenshot && !FileManager.default.fileExists(atPath: $0.urls[0].path) })
        let prefixes = Self.screenshotPrefixes()
        // старше срока хранения не берём; при «Всегда» — только за последние сутки
        let age = retention == .forever ? 86400 : TimeInterval(retention.rawValue)
        let cutoff = Date().addingTimeInterval(-age)
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: Self.screenshotDir(), includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            screenshotsDenied = false
        } catch {
            screenshotsDenied = Self.isPermissionError(error)
            urls = []
        }
        let found: [(URL, Date)] = urls.compactMap { u in
            let n = u.lastPathComponent.lowercased()
            guard ["png", "jpg", "jpeg", "heic"].contains(u.pathExtension.lowercased()),
                  prefixes.contains(where: n.hasPrefix),
                  let d = try? u.resourceValues(forKeys: [.creationDateKey]).creationDate, d > cutoff
            else { return nil }
            return (u, d)
        }
        for (u, d) in found.sorted(by: { $0.1 > $1.1 }).prefix(8) where !seenShots.contains(u.path) {
            seenShots.append(u.path)
            add(ClipItem(kind: .screenshot, text: u.lastPathComponent, urls: [u], date: d, key: "shot:" + u.path))
        }
        if seenShots.count > 200 { seenShots.removeFirst(seenShots.count - 200) }
        return items.contains { $0.kind == .screenshot && Date().timeIntervalSince($0.date) < 15 }
    }

    // MARK: Доступ к папке со скриншотами

    /// «Рабочий стол», «Документы», «Загрузки»; другие папки — как их называет Finder
    var screenshotFolderName: String {
        let dir = Self.screenshotDir()
        switch Self.privacyService(for: dir) {
        case "SystemPolicyDesktopFolder": return "Рабочий стол"
        case "SystemPolicyDocumentsFolder": return "Документы"
        case "SystemPolicyDownloadsFolder": return "Загрузки"
        default: return FileManager.default.displayName(atPath: dir.path)
        }
    }

    /// Кнопка «Разрешить». После отказа macOS сама больше не спрашивает: сбрасываем отказ только
    /// для нашего приложения — и при следующем чтении папки macOS показывает своё окно снова.
    /// Окно держит чтение, пока на него не ответят, поэтому мгновенный повторный отказ значит:
    /// окна не было. Тогда, как и при неудачном сбросе, открываем «Конфиденциальность → Файлы и папки»
    func requestScreenshotAccess() {
        guard let service = Self.privacyService(for: Self.screenshotDir()),
              let id = Bundle.main.bundleIdentifier, Self.resetPrivacy(service, for: id) else {
            return Self.openFilesAndFoldersSettings()
        }
        let start = Date()
        scanScreenshots()
        if screenshotsDenied && Date().timeIntervalSince(start) < 0.5 { Self.openFilesAndFoldersSettings() }
    }

    /// Защищённые папки и их разрешения в macOS; остальные папки читаются без спроса
    static func privacyService(for dir: URL) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = dir.standardizedFileURL.path
        func under(_ name: String) -> Bool { path == home + "/" + name || path.hasPrefix(home + "/" + name + "/") }
        if under("Desktop") { return "SystemPolicyDesktopFolder" }
        if under("Documents") { return "SystemPolicyDocumentsFolder" }
        if under("Downloads") { return "SystemPolicyDownloadsFolder" }
        return nil
    }

    private static func resetPrivacy(_ service: String, for bundleID: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", service, bundleID]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func openFilesAndFoldersSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoPermissionError { return true }
        let posix = (e.userInfo[NSUnderlyingErrorKey] as? NSError) ?? e
        return posix.domain == NSPOSIXErrorDomain && (posix.code == Int(EPERM) || posix.code == Int(EACCES))
    }

    // MARK: Действия

    /// Копирует запись обратно в буфер (порядок списка не меняем)
    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text: pb.setString(item.text, forType: .string)
        case .image, .screenshot:
            if let url = item.urls.first, let img = NSImage(contentsOf: url) { pb.writeObjects([img]) }
        case .files: pb.writeObjects(item.urls as [NSURL])
        }
        lastCount = pb.changeCount
    }

    /// Что отдать при перетаскивании записи в другое окно
    func dragProvider(_ item: ClipItem) -> NSItemProvider {
        if item.kind == .text { return NSItemProvider(object: item.text as NSString) }
        return item.urls.first.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
    }

    func remove(_ item: ClipItem) { remove([item]) }

    /// Убираем просроченное (если срок не «Всегда») и лишнее сверх лимита
    func prune() {
        var gone: [ClipItem] = []
        var kept = items
        if retention != .forever {
            let cutoff = Date().addingTimeInterval(-TimeInterval(retention.rawValue))
            gone = kept.filter { $0.date < cutoff }
            kept.removeAll { $0.date < cutoff }
        }
        if kept.count > Self.limit { gone += kept.suffix(kept.count - Self.limit) }
        remove(gone)
    }

    private func remove(_ gone: [ClipItem]) {
        guard !gone.isEmpty else { return }
        let ids = Set(gone.map(\.id))
        items.removeAll { ids.contains($0.id) }
        // копии картинок — наши, удаляем; файлы и скриншоты на диске не трогаем
        let files = gone.filter { $0.kind == .image }.compactMap(\.urls.first)
        io.async { files.forEach { try? FileManager.default.removeItem(at: $0) } }
        save()
    }

    // MARK: Диск

    private struct Saved: Codable {
        var items: [ClipItem]
        var seenShots: [String]
    }

    private static func makeDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        items = saved.items.filter { $0.kind != .image || FileManager.default.fileExists(atPath: $0.urls[0].path) }
        seenShots = saved.seenShots
        prune()
        // копии картинок, на которые не ссылается ни одна запись (например, после сбоя)
        let used = Set(items.filter { $0.kind == .image }.map { $0.urls[0].lastPathComponent })
        io.async {
            let all = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
            for u in all where u.pathExtension == "png" && !used.contains(u.lastPathComponent) {
                try? FileManager.default.removeItem(at: u)
            }
        }
    }

    /// Пишем с небольшой задержкой: серия изменений — одна запись на диск
    private func save() {
        saveWork?.cancel()
        let saved = Saved(items: items, seenShots: seenShots)
        let work = DispatchWorkItem {
            Self.makeDir()
            guard let data = try? JSONEncoder().encode(saved) else { return }
            try? data.write(to: Self.file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
        }
        saveWork = work
        io.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
