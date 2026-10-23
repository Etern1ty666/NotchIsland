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
    @Published private(set) var items: [ClipItem] = [] {
        // удалённые (крестиком, по сроку хранения) выпадают и из выбора
        didSet { if !selection.isEmpty { selection.removeAll { id in !items.contains { $0.id == id } } } }
    }
    /// macOS не даёт читать папку со скриншотами (в окне доступа нажали «Не разрешать»)
    @Published private(set) var screenshotsDenied = false
    @Published var retention = ClipRetention(rawValue: UserDefaults.standard.object(forKey: DefaultsKey.clipRetention) as? Int
                                             ?? ClipRetention.forever.rawValue) ?? .forever {
        didSet {
            UserDefaults.standard.set(retention.rawValue, forKey: DefaultsKey.clipRetention)
            prune()
        }
    }
    /// Подсказки под записями; спрятать — кнопкой у их заголовка, вернуть — в настройках
    @Published var showTips = UserDefaults.standard.object(forKey: DefaultsKey.clipTips) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showTips, forKey: DefaultsKey.clipTips) }
    }

    /// Удалённое крестиком или «Очистить историю» — ещё можно вернуть (плашка «Вернуть»)
    struct Deletion: Equatable {
        let id = UUID()
        let items: [ClipItem]
        /// Очистили всю историю, а не одну запись
        let all: Bool
    }
    @Published private(set) var deletion: Deletion?
    /// Выбранные ⌘-кликом на острове — в порядке выбора: так они и скопируются вместе.
    /// Снимается Esc, обычным кликом и при сворачивании острова
    @Published var selection: [UUID] = []
    /// Только что скопированные с острова — на них «Скопировано»; гаснет само
    @Published private(set) var copied: Set<UUID> = []
    private var copiedWork: DispatchWorkItem?
    /// Сколько держится «Вернуть»; потом копии картинок стираются с диска
    static let undoTime: TimeInterval = 5
    private var deletionWork: DispatchWorkItem?

    private var lastCount = NSPasteboard.general.changeCount
    /// Скриншоты, которые уже побывали в ленте: удалённый из ленты не вернётся
    private var seenShots: [String] = []
    /// Диск — по очереди: запись истории, сохранение и удаление картинок
    private let io = DispatchQueue(label: "NotchIsland.clipboard")
    private var saveWork: DispatchWorkItem?
    private var timers: [Timer] = []
    /// Слежка за папкой со скриншотами: новый попадает в ленту, как только macOS его сохранит, — и при открытом острове
    private var shotWatch: DispatchSourceFileSystemObject?
    private var shotWatchDir: URL?
    private var shotScanWork: DispatchWorkItem?

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

    /// Новые скриншоты из папки — в ленту (при раскрытии острова и при каждом изменении папки). true — есть совсем свежий
    @discardableResult
    func scanScreenshots() -> Bool {
        // удалённые с диска убираем и из ленты
        remove(items.filter { $0.kind == .screenshot && !FileManager.default.fileExists(atPath: $0.urls[0].path) })
        let prefixes = Self.screenshotPrefixes()
        // старше срока хранения не берём; при «Всегда» — только за последние сутки
        let age = retention == .forever ? 86400 : TimeInterval(retention.rawValue)
        let cutoff = Date().addingTimeInterval(-age)
        let urls: [URL]
        let dir = Self.screenshotDir()
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            screenshotsDenied = false
            // следим, только когда папку уже дали читать: иначе macOS спросила бы доступ сразу при запуске
            watchScreenshots(dir)
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

    /// Пока на экране миниатюра скриншота, macOS держит снимок в памяти и пишет файл, только когда миниатюра
    /// уйдёт (или её смахнут вправо). Ловим этот момент по изменению папки, а не ждём раскрытия острова.
    /// Сменили папку для скриншотов — следим за новой
    private func watchScreenshots(_ dir: URL) {
        guard dir != shotWatchDir else { return }
        shotWatch?.cancel()
        shotWatch = nil
        shotWatchDir = nil
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            // саму папку переименовали или удалили — следить больше не за чем, переподключимся при скане
            if !source.data.isDisjoint(with: [.rename, .delete]) {
                source.cancel()
                self.shotWatch = nil
                self.shotWatchDir = nil
            }
            self.scheduleShotScan()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        shotWatch = source
        shotWatchDir = dir
    }

    /// macOS пишет скриншот скрытым файлом и тут же переименовывает — событий пачка, сканируем раз на пачку
    private func scheduleShotScan() {
        shotScanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanScreenshots() }
        shotScanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: Доступ к папке со скриншотами

    /// «Рабочий стол», «Документы», «Загрузки»; другие папки — как их называет Finder
    var screenshotFolderName: String {
        let dir = Self.screenshotDir()
        switch Self.privacyService(for: dir) {
        case "SystemPolicyDesktopFolder": return L("Рабочий стол")
        case "SystemPolicyDocumentsFolder": return L("Документы")
        case "SystemPolicyDownloadsFolder": return L("Загрузки")
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
        markCopied([item.id])
    }

    /// Несколько записей разом, в порядке выбора. Одни тексты — одним текстом, каждый с новой строки;
    /// иначе каждая запись — отдельным элементом буфера: текст текстом, картинки, скриншоты и файлы — файлами.
    /// Файлами Finder, почта и мессенджеры вставляют всё сразу, а картинками — часто только первую
    func copy(_ list: [ClipItem]) {
        guard list.count > 1 else {
            if let item = list.first { copy(item) }
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        if list.allSatisfy({ $0.kind == .text }) {
            pb.setString(list.map(\.text).joined(separator: "\n"), forType: .string)
        } else {
            pb.writeObjects(list.flatMap { item -> [NSPasteboardWriting] in
                item.kind == .text ? [item.text as NSString] : item.urls.map { $0 as NSURL }
            })
        }
        lastCount = pb.changeCount
        markCopied(list.map(\.id))
    }

    /// Остров после копирования не сворачивается — «Скопировано» на записях гаснет само
    private func markCopied(_ ids: [UUID]) {
        copiedWork?.cancel()
        copied = Set(ids)
        let work = DispatchWorkItem { [weak self] in self?.copied = [] }
        copiedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Остров раскрыли заново — прежних «Скопировано» уже нет
    func clearCopiedMarks() {
        copiedWork?.cancel()
        copiedWork = nil
        if !copied.isEmpty { copied = [] }
    }

    // MARK: Выбор нескольких записей (⌘-клик)

    var selectedItems: [ClipItem] {
        selection.compactMap { id in items.first { $0.id == id } }
    }

    /// ⌘-клик: добавить запись к выбору или убрать из него
    func toggleSelection(_ item: ClipItem) {
        if let i = selection.firstIndex(of: item.id) { selection.remove(at: i) } else { selection.append(item.id) }
    }

    func clearSelection() {
        if !selection.isEmpty { selection = [] }
    }

    /// Выбранные — в буфер вместе; выбор снимается, на записях загорается «Скопировано»
    func copySelection() {
        copy(selectedItems)
        clearSelection()
    }

    /// Выбранные — из истории, одной плашкой «Вернуть»; из выбора они выпадают сами
    func deleteSelection() {
        delete(selectedItems)
    }

    /// Что отдать при перетаскивании записи в другое окно
    func dragProvider(_ item: ClipItem) -> NSItemProvider {
        if item.kind == .text { return NSItemProvider(object: item.text as NSString) }
        return item.urls.first.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
    }

    /// Крестик на записи и «Очистить историю»: записи пропадают сразу, но несколько секунд их можно вернуть.
    /// Вернуть можно только последнее удаление
    func delete(_ gone: [ClipItem], all: Bool = false) {
        guard !gone.isEmpty else { return }
        commitDeletion()
        let ids = Set(gone.map(\.id))
        items.removeAll { ids.contains($0.id) }
        save()
        deletion = Deletion(items: gone, all: all)
        let work = DispatchWorkItem { [weak self] in self?.commitDeletion() }
        deletionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoTime, execute: work)
    }

    func clearHistory() { delete(items, all: true) }

    /// «Вернуть»: записи встают на свои места по времени. Скопированное заново за эти секунды не дублируем
    func undoDeletion() {
        guard let d = deletion else { return }
        deletionWork?.cancel()
        deletionWork = nil
        deletion = nil
        for item in d.items where !items.contains(where: { $0.identity == item.identity }) {
            items.insert(item, at: items.firstIndex { $0.date < item.date } ?? items.count)
        }
        prune()
        save()
    }

    /// Вернуть уже нельзя — стираем копии картинок
    private func commitDeletion() {
        deletionWork?.cancel()
        deletionWork = nil
        guard let d = deletion else { return }
        deletion = nil
        deleteImages(of: d.items)
    }

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
        deleteImages(of: gone)
        save()
    }

    /// Копии картинок — наши, удаляем, если на ту же копию не ссылается запись в ленте (картинку могли
    /// скопировать снова); файлы и скриншоты на диске не трогаем
    private func deleteImages(of gone: [ClipItem]) {
        let used = Set(items.flatMap(\.urls))
        let files = gone.filter { $0.kind == .image }.compactMap(\.urls.first).filter { !used.contains($0) }
        io.async { files.forEach { try? FileManager.default.removeItem(at: $0) } }
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
