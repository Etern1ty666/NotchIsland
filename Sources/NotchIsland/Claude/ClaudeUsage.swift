import SwiftUI
import AppKit
import Security

/// Лимиты подписки (сессия 5 ч и неделя, как в /usage) — из двух источников:
/// • вход Claude Code (`claude auth login`): раз в минуту спрашиваем сервер Anthropic напрямую.
///   Учитывается всё — приложение Claude, браузер, терминал. Адрес неофициальный (им пользуется
///   сам Claude Code для /usage), может перестать работать после обновлений;
/// • строка состояния Claude Code в терминале (`NotchIsland --statusline`) — официально, но только
///   после ответов в терминале
@MainActor
final class ClaudeUsage: ObservableObject {
    /// Раз в минуту; если сервер ответит «слишком часто» (429), ждём, сколько он просит
    static let pollInterval: TimeInterval = 60

    /// Сюда пишет лимиты строка состояния Claude Code (`NotchIsland --statusline`)
    nonisolated static let file = AppPaths.support.appendingPathComponent("claude-usage.json")
    static let claudeSettings = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    @Published private(set) var fiveHour: UsageWindow?
    @Published private(set) var sevenDay: UsageWindow?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var connection: Connection = .none
    /// Вход Claude Code есть в связке ключей
    @Published private(set) var loggedIn = false
    /// Кнопка «Войти»: запускаем `claude auth login` сами, пользователю остаётся войти в браузере
    @Published private(set) var login: LoginState = .idle
    private var loginProcess: Process?

    enum LoginState: Equatable {
        case idle
        case waiting(URL?)       // ждём вход в браузере; ссылка — если Claude Code её напечатал
        case failed(String)
    }
    @Published private(set) var apiError: String?
    /// Идёт запрос к серверу — кнопка «обновить» ждёт
    @Published private(set) var fetching = false
    private var nextFetch = Date()
    /// Сервер отказал в доступе — не долбим его, пока вход не сменится
    private var blockedToken: String?

    enum Connection: Equatable {
        case none        // строка состояния Claude Code не настроена
        case ours        // подключено к нам
        case other       // у пользователя своя строка состояния — не трогаем без спроса
    }

    private var fileDate: Date?
    private var timer: Timer?

    init() {
        Self.removeOldToken()
        refreshConnection()
        reload()
        Task { await fetch() }
        // файл маленький, проверяем дату изменения раз в 3 секунды — дёшево;
        // сервер — по расписанию nextFetch
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reload()
                // пока идёт вход — проверяем почаще, чтобы цифры появились сразу после него
                if case .waiting = self.login, !self.loggedIn { self.nextFetch = min(self.nextFetch, Date()) }
                if Date() >= self.nextFetch { Task { await self.fetch() } }
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func reload() {
        let date = (try? Self.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let date, date != fileDate,
              let data = try? Data(contentsOf: Self.file),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            objectWillChange.send()   // «сброс через N мин» и isReset зависят от времени
            return
        }
        fileDate = date
        let at = (json["updated_at"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? date
        // свежее, чем ответ сервера, — берём
        if updatedAt.map({ at > $0 }) ?? true {
            apply(Self.window(json["five_hour"]), Self.window(json["seven_day"]), at: at)
        }
    }

    private func apply(_ five: UsageWindow?, _ seven: UsageWindow?, at: Date) {
        fiveHour = five
        sevenDay = seven
        updatedAt = at
    }

    /// Окно из JSON: проценты — used_percentage (строка состояния) или utilization (сервер),
    /// сброс — секунды Unix или строка ISO 8601
    private static func window(_ any: Any?) -> UsageWindow? {
        guard let d = any as? [String: Any],
              let used = ((d["used_percentage"] ?? d["utilization"]) as? NSNumber)?.doubleValue else { return nil }
        var reset: Date?
        if let n = d["resets_at"] as? NSNumber { reset = Date(timeIntervalSince1970: n.doubleValue) }
        if let str = d["resets_at"] as? String { reset = parseISODate(str) }
        return UsageWindow(used: used / 100, resetsAt: reset)
    }

    // MARK: Сервер лимитов

    /// Токен из `claude setup-token` (прошлая версия хранила его у себя) лимиты не видит — удаляем
    private static func removeOldToken() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "com.notchisland.app",
                                kSecAttrAccount as String: "claude-oauth-token"]
        SecItemDelete(q as CFDictionary)
    }

    func window(_ w: ClaudeWidget) -> UsageWindow? {
        switch w {
        case .session: return fiveHour
        case .week: return sevenDay
        }
    }

    /// Подсказка при наведении на «таблетку» в строке меню
    func summary(_ w: ClaudeWidget) -> String {
        guard let win = window(w) else { return "Claude · \(w.title): нет данных" }
        let spent = (win.spent * 100).rounded() > 0 ? "израсходовано \(pct(win.spent))" : "лимит не тронут (0%)"
        return "Claude · \(w.title): \(spent), \(resetText(win.resetsAt))"
    }

    /// Кнопка «обновить»: перечитываем файл строки состояния и сразу спрашиваем сервер
    func refresh() {
        reload()
        Task { await fetch() }
    }

    func fetch() async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        nextFetch = Date().addingTimeInterval(Self.pollInterval)
        // чтение связки ключей — внешний процесс, уводим с главного потока
        guard var creds = await Task.detached(operation: { ClaudeCodeLogin.read() }).value, creds.isLoggedIn else {
            loggedIn = false
            apiError = nil
            return
        }
        loggedIn = true
        if case .waiting = login { finishLogin() }
        if blockedToken == creds.accessToken { return }
        do {
            if creds.expiresAt.timeIntervalSinceNow < 60 { creds = try await ClaudeCodeLogin.refresh(creds) }
            var (status, json, retry) = try await requestUsage(creds.accessToken)
            if status == 401 {
                creds = try await ClaudeCodeLogin.refresh(creds)
                (status, json, retry) = try await requestUsage(creds.accessToken)
            }
            switch status {
            case 200:
                let five = Self.window(json["five_hour"]), seven = Self.window(json["seven_day"])
                guard five != nil || seven != nil else { apiError = "Сервер не прислал лимиты"; return }
                apply(five, seven, at: Date())
                apiError = nil
            case 429:
                // слишком часто — ждём, сколько просит сервер (но не меньше 5 минут)
                nextFetch = Date().addingTimeInterval(max(retry ?? 0, 300))
                apiError = "Сервер просит подождать — повторю через \(formatMinutes(Int(max(retry ?? 0, 300) / 60)))"
            case 403:
                blockedToken = creds.accessToken
                apiError = "У входа нет доступа к лимитам — войди заново: claude auth login"
            default:
                apiError = ((json["error"] as? [String: Any])?["message"] as? String) ?? "Ошибка сервера (HTTP \(status))"
            }
        } catch ClaudeCodeLogin.RefreshError.expired {
            apiError = "Вход Claude Code устарел — войди заново: claude auth login"
        } catch ClaudeCodeLogin.RefreshError.network(let m) {
            apiError = m
        } catch {
            apiError = error.localizedDescription
        }
    }

    private func requestUsage(_ token: String) async throws -> (Int, [String: Any], TimeInterval?) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 20
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("NotchIsland/1.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let retry = http?.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
        return (http?.statusCode ?? 0, json, retry)
    }

    // MARK: Вход в Claude Code

    /// Где лежит `claude`: Homebrew, npm, родной установщик
    static func findClaude() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.local/bin/claude",
                          "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// Запускаем вход в фоне: Claude Code сам откроет браузер и сохранит вход в связку ключей
    func startLogin() {
        guard let bin = Self.findClaude() else {
            login = .failed("Claude Code не установлен — нужен для входа")
            return
        }
        loginProcess?.terminate()
        let p = Process()
        p.executableURL = bin
        p.arguments = ["auth", "login", "--claudeai"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        p.standardInput = Pipe()   // не закрываем: без терминала Claude Code не должен ждать ввода
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let text = String(data: h.availableData, encoding: .utf8) ?? ""
            // ссылку на вход запоминаем — вдруг браузер не открылся сам
            guard let r = text.range(of: #"https://\S+"#, options: .regularExpression),
                  let url = URL(string: String(text[r])), url.absoluteString.contains("oauth") else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.login = .waiting(url) } }
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.loginEnded(code) } }
        }
        do {
            try p.run()
            loginProcess = p
            login = .waiting(nil)
            // десять минут на вход — дальше бросаем, чтобы процесс не висел
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self, weak p] in
                guard let self, let p, p.isRunning, self.loginProcess === p else { return }
                p.terminate()
            }
        } catch {
            login = .failed("Не удалось запустить вход: \(error.localizedDescription)")
        }
    }

    private func loginEnded(_ code: Int32) {
        loginProcess = nil
        guard case .waiting = login else { return }
        if code == 0 {
            finishLogin()
            fetchNow()
        } else {
            login = .failed("Вход не завершён — попробуй ещё раз или открой в Терминале")
        }
    }

    private func finishLogin() {
        login = .idle
        loginProcess?.terminate()
        loginProcess = nil
    }

    func cancelLogin() {
        loginProcess?.terminate()
        loginProcess = nil
        login = .idle
    }

    /// Запасной путь: та же команда в окне Терминала (если вход попросит что-то ввести)
    func loginInTerminal() {
        let bin = Self.findClaude()?.path ?? "claude"
        let script = "#!/bin/zsh\n\"\(bin)\" auth login --claudeai\necho\necho 'Готово — окно можно закрыть.'\n"
        let url = AppPaths.support.appendingPathComponent("claude-login.command")
        do {
            try FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
            login = .waiting(nil)
        } catch {
            login = .failed(error.localizedDescription)
        }
    }

    /// Проверить сейчас (кнопка в настройках) — если сервер не просил подождать
    func fetchNow() {
        if apiError?.hasPrefix("Сервер просит подождать") == true { return }
        blockedToken = nil
        Task { await fetch() }
    }

    // MARK: Подключение к Claude Code

    /// Команда, которую Claude Code запускает как строку состояния
    static var command: String { "\"\(Bundle.main.executablePath ?? "/Applications/NotchIsland.app/Contents/MacOS/NotchIsland")\" --statusline" }

    private static func readSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: claudeSettings),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return json
    }

    func refreshConnection() {
        guard let line = Self.readSettings()["statusLine"] as? [String: Any] else { connection = .none; return }
        connection = (line["command"] as? String)?.contains("--statusline") == true
            && (line["command"] as? String)?.contains("NotchIsland") == true ? .ours : .other
    }

    /// Прописываем себя строкой состояния в ~/.claude/settings.json. Прежний файл
    /// сохраняем рядом (settings.json.notchisland-backup), остальные настройки не трогаем
    func connect() -> String? {
        var settings = Self.readSettings()
        settings["statusLine"] = ["type": "command", "command": Self.command]
        return writeSettings(settings)
    }

    func disconnect() -> String? {
        var settings = Self.readSettings()
        settings.removeValue(forKey: "statusLine")
        return writeSettings(settings)
    }

    private func writeSettings(_ settings: [String: Any]) -> String? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: Self.claudeSettings.path) {
                let backup = Self.claudeSettings.appendingPathExtension("notchisland-backup")
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: Self.claudeSettings, to: backup)
            }
            let data = try JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: Self.claudeSettings, options: .atomic)
            refreshConnection()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Режим строки состояния

    /// `NotchIsland --statusline`: Claude Code передаёт JSON на stdin. Сохраняем лимиты для острова
    /// и печатаем короткую строку — её Claude Code покажет внизу терминала
    nonisolated static func runStatusLine() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        guard let limits = json["rate_limits"] as? [String: Any],
              limits["five_hour"] != nil || limits["seven_day"] != nil else { return }
        var out = limits
        out["updated_at"] = Date().timeIntervalSince1970
        if let data = try? JSONSerialization.data(withJSONObject: out) {
            try? FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        func pct(_ key: String) -> String? {
            ((limits[key] as? [String: Any])?["used_percentage"] as? NSNumber)
                .map { "\(Int($0.doubleValue.rounded()))%" }
        }
        let parts = [pct("five_hour").map { "сессия \($0)" }, pct("seven_day").map { "неделя \($0)" }].compactMap { $0 }
        print("Claude: " + parts.joined(separator: " · "))
    }
}
