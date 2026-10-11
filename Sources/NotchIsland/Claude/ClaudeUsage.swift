import SwiftUI
import AppKit
import Security

/// Лимиты подписки (сессия 5 ч и неделя, как в /usage) через вход Claude Code (`claude auth login`):
/// раз в минуту спрашиваем сервер Anthropic напрямую. Учитывается всё — приложение Claude, браузер,
/// терминал. Адрес неофициальный (им пользуется сам Claude Code для /usage), может перестать
/// работать после обновлений
@MainActor
final class ClaudeUsage: ObservableObject {
    /// Раз в минуту; если сервер ответит «слишком часто» (429), ждём, сколько он просит
    static let pollInterval: TimeInterval = 60

    @Published private(set) var fiveHour: UsageWindow?
    @Published private(set) var sevenDay: UsageWindow?
    @Published private(set) var updatedAt: Date?
    /// Вход Claude Code есть в связке ключей
    @Published private(set) var loggedIn = false
    /// Связку ключей уже прочитали — до этого не знаем, есть ли вход (и не пишем «Подключите Claude»)
    @Published private(set) var loginChecked = false
    /// Вход пропал: устарел или у него больше нет доступа к лимитам — нужно войти заново.
    /// Только тогда значок аккаунта в настройках красный; «подожди» и сбои сети — не повод
    @Published private(set) var authLost = false
    /// Брать лимиты через вход Claude Code. «Отключить» в настройках только перестаёт спрашивать
    /// сервер — из самого Claude Code не выходим, терминал продолжает работать
    @Published private(set) var accountEnabled = UserDefaults.standard.object(forKey: DefaultsKey.claudeAccount) as? Bool ?? true
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
    /// Сервер попросил подождать — до этого времени не спрашиваем, даже по кнопке
    private var waitUntil: Date?

    /// Аккаунта нет: отключён, не вошли или вход пропал. В строке меню — «Подключите Claude»
    var needsAccount: Bool { !accountEnabled || (loginChecked && (!loggedIn || authLost)) }

    private var ticks = 0
    private var timer: Timer?

    init() {
        Self.removeOldToken()
        Self.removeStatusLine()
        Task { await fetch() }
        // сервер — по расписанию nextFetch; раз в 30 с перерисовываем «сброс через N мин»
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.ticks += 1
                if self.ticks % 10 == 0 { self.objectWillChange.send() }
                // пока идёт вход — проверяем почаще, чтобы цифры появились сразу после него
                if case .waiting = self.login, !self.loggedIn { self.nextFetch = min(self.nextFetch, Date()) }
                if Date() >= self.nextFetch { Task { await self.fetch() } }
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func apply(_ five: UsageWindow?, _ seven: UsageWindow?, at: Date) {
        fiveHour = five
        sevenDay = seven
        updatedAt = at
    }

    /// Окно из ответа сервера: проценты — utilization, сброс — секунды Unix или строка ISO 8601
    private static func window(_ any: Any?) -> UsageWindow? {
        guard let d = any as? [String: Any],
              let used = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
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

    /// «Подключить Claude» в меню значка: отключённый аккаунт — включаем, нет входа — входим
    func connect() {
        if !accountEnabled { setAccountEnabled(true) } else if !loggedIn || authLost { startLogin() }
    }

    /// Подсказка при наведении на «таблетку» в строке меню
    func summary(_ w: ClaudeWidget) -> String {
        if needsAccount { return L("Claude · %@: аккаунт не подключён", w.title) }
        guard let win = window(w) else { return L("Claude · %@: нет данных", w.title) }
        let spent = (win.spent * 100).rounded() > 0 ? L("израсходовано %@", pct(win.spent)) : L("лимит не тронут (0%)")
        return L("Claude · %@: %@, %@", w.title, spent, resetText(win.resetsAt))
    }

    /// Кнопка «обновить» на вкладке статистики
    func refresh() {
        Task { await fetch() }
    }

    func fetch() async {
        guard accountEnabled, !fetching else { return }
        fetching = true
        defer { fetching = false }
        nextFetch = Date().addingTimeInterval(Self.pollInterval)
        // чтение связки ключей — внешний процесс, уводим с главного потока
        let read = await Task.detached(operation: { ClaudeCodeLogin.read() }).value
        loginChecked = true
        guard var creds = read, creds.isLoggedIn else {
            loggedIn = false
            authLost = false
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
                guard five != nil || seven != nil else { apiError = L("Сервер не прислал лимиты"); return }
                apply(five, seven, at: Date())
                apiError = nil
                authLost = false
                waitUntil = nil
            case 429:
                // слишком часто — ждём, сколько просит сервер (но не меньше 5 минут)
                let wait = max(retry ?? 0, 300)
                nextFetch = Date().addingTimeInterval(wait)
                waitUntil = nextFetch
                apiError = L("Повтор через %@", formatMinutes(Int(wait / 60)))
            case 401, 403:
                blockedToken = creds.accessToken
                authLost = true
                apiError = L("Вход больше не действует")
            default:
                apiError = ((json["error"] as? [String: Any])?["message"] as? String) ?? L("Ошибка сервера (HTTP %@)", String(status))
            }
        } catch ClaudeCodeLogin.RefreshError.expired {
            authLost = true
            apiError = L("Вход устарел, нужно войти заново")
        } catch ClaudeCodeLogin.RefreshError.network(let m) {
            apiError = m
        } catch let e as URLError where e.code == .timedOut || e.code == .cannotConnectToHost {
            apiError = L("Сервер не отвечает")
        } catch is URLError {
            apiError = L("Нет сети")
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
            login = .failed(L("Claude Code не установлен — нужен для входа"))
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
            login = .failed(L("Не удалось запустить вход: %@", error.localizedDescription))
        }
    }

    private func loginEnded(_ code: Int32) {
        loginProcess = nil
        guard case .waiting = login else { return }
        if code == 0 {
            finishLogin()
            fetchNow()
        } else {
            login = .failed(L("Вход не завершён — можно повторить или войти через Терминал"))
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
        let script = "#!/bin/zsh\n\"\(bin)\" auth login --claudeai\necho\necho '\(L("Готово — окно можно закрыть."))'\n"
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

    /// Подключить или отключить аккаунт: отключённый не спрашивает сервер, цифр лимитов нет
    func setAccountEnabled(_ on: Bool) {
        accountEnabled = on
        UserDefaults.standard.set(on, forKey: DefaultsKey.claudeAccount)
        apiError = nil
        authLost = false
        if on {
            fetchNow()
        } else {
            fiveHour = nil
            sevenDay = nil
            updatedAt = nil
        }
    }

    /// Проверить сейчас (кнопка в настройках) — если сервер не просил подождать
    func fetchNow() {
        if let waitUntil, waitUntil > Date() { return }
        blockedToken = nil
        Task { await fetch() }
    }

    // MARK: Уборка за прежними версиями

    /// Прежние версии брали лимиты ещё и из строки состояния Claude Code в терминале.
    /// Этот источник убран: отключаем строку состояния, если она наша (чужую не трогаем),
    /// и удаляем файл, куда она писала. Копия настроек — рядом, settings.json.notchisland-backup
    private static func removeStatusLine() {
        try? FileManager.default.removeItem(at: AppPaths.support.appendingPathComponent("claude-usage.json"))
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let command = (json["statusLine"] as? [String: Any])?["command"] as? String,
              command.contains("NotchIsland"), command.contains("--statusline") else { return }
        json.removeValue(forKey: "statusLine")
        guard let out = try? JSONSerialization.data(withJSONObject: json,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return }
        let backup = url.appendingPathExtension("notchisland-backup")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)
        try? out.write(to: url, options: .atomic)
    }
}
