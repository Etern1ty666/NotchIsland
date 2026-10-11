import AppKit

/// Вход Claude Code (`claude auth login`) в связке ключей macOS, запись «Claude Code-credentials».
/// Читаем и пишем её через системную утилиту `security` — так же, как сам Claude Code: она уже
/// в списке доверенных у этой записи, поэтому macOS не спрашивает разрешения (и после пересборки тоже)
enum ClaudeCodeLogin {
    static let service = "Claude Code-credentials"
    /// Публичный идентификатор приложения Claude Code для обновления входа
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

    struct Credentials {
        var json: [String: Any]          // запись целиком — остальные поля сохраняем как есть
        var oauth: [String: Any] { json["claudeAiOauth"] as? [String: Any] ?? [:] }
        var accessToken: String { oauth["accessToken"] as? String ?? "" }
        var refreshToken: String { oauth["refreshToken"] as? String ?? "" }
        var scopes: [String] { oauth["scopes"] as? [String] ?? [] }
        var expiresAt: Date { Date(timeIntervalSince1970: ((oauth["expiresAt"] as? NSNumber)?.doubleValue ?? 0) / 1000) }
        var isLoggedIn: Bool { !accessToken.isEmpty || !refreshToken.isEmpty }
    }

    private static func security(_ args: [String], stdin: String? = nil) -> (status: Int32, out: Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        if stdin != nil { p.standardInput = inp }
        do { try p.run() } catch { return (-1, Data()) }
        if let stdin {
            inp.fileHandleForWriting.write(Data(stdin.utf8))
            try? inp.fileHandleForWriting.close()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }

    static func read() -> Credentials? {
        let r = security(["find-generic-password", "-s", service, "-w"])
        guard r.status == 0,
              let json = (try? JSONSerialization.jsonObject(with: r.out)) as? [String: Any] else { return nil }
        return Credentials(json: json)
    }

    /// Секрет передаём через stdin в шестнадцатеричном виде (-X), а не аргументом командной строки —
    /// иначе он был бы виден в списке процессов
    static func write(_ c: Credentials) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: c.json) else { return false }
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let cmd = "add-generic-password -U -a \"\(NSUserName())\" -s \"\(service)\" -X \"\(hex)\"\n"
        return security(["-i"], stdin: cmd).status == 0
    }

    /// expired — вход отозван, нужно войти заново; busy — вход сейчас обновляет Claude Code, повторим скоро
    enum RefreshError: Error { case expired, busy, network(String) }

    /// Обновляем вход, когда до конца осталось меньше минуты. Claude Code берётся за это за 5 минут —
    /// если он запущен, обычно успевает первым, и мы просто читаем его новые токены
    static let refreshMargin: TimeInterval = 60

    /// Обновляем вход так же, как Claude Code, и записываем новые токены обратно в связку ключей —
    /// чтобы и сам Claude Code продолжил работать. Ключ обновления одноразовый: кто обновил вторым
    /// со старым ключом, тот получает отказ, а сервер может отозвать вход целиком. Поэтому — под той же
    /// блокировкой, что и Claude Code, и сначала смотрим, не обновил ли он вход, пока мы ждали.
    /// force — сервер отказал токену, хотя срок ещё не вышел
    static func refresh(_ c: Credentials, force: Bool = false) async throws -> Credentials {
        try await withRefreshLock {
            guard let now = read() else { throw RefreshError.busy }
            guard now.isLoggedIn else { throw RefreshError.expired }
            if now.accessToken != c.accessToken { return now }
            if !force && now.expiresAt.timeIntervalSinceNow > refreshMargin { return now }
            do {
                return try await requestRefresh(now)
            } catch RefreshError.expired {
                // вдруг обновил кто-то без блокировки (старый Claude Code) — тогда берём его вход
                if let after = read(), after.isLoggedIn, after.accessToken != now.accessToken { return after }
                throw RefreshError.expired
            }
        }
    }

    // MARK: Блокировка обновления

    /// Claude Code обновляет вход под блокировкой в своей папке: ~/.claude/.oauth_refresh.lock
    /// и прежняя ~/.claude.lock (берёт обе, в этом порядке) — берём те же
    private static let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    private static var lockPaths: [URL] {
        [configDir.appendingPathComponent(".oauth_refresh.lock"),
         URL(fileURLWithPath: configDir.resolvingSymlinksInPath().path + ".lock")]
    }
    /// Как у proper-lockfile, которой пользуется Claude Code: блокировка — папка, создаётся атомарно;
    /// не обновлявшаяся дольше 10 с считается брошенной, свою держатель трогает каждые 5 с
    private static let lockStale: TimeInterval = 10

    private static func tryLock(_ url: URL) -> Bool {
        let fm = FileManager.default
        if (try? fm.createDirectory(at: url, withIntermediateDirectories: false)) != nil { return true }
        guard let m = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              Date().timeIntervalSince(m) > lockStale else { return false }
        try? fm.removeItem(at: url)
        return (try? fm.createDirectory(at: url, withIntermediateDirectories: false)) != nil
    }

    private static func withRefreshLock<T>(_ body: () async throws -> T) async throws -> T {
        let fm = FileManager.default
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        let paths = lockPaths
        var acquired = false
        // занято — ждём, как Claude Code, по 1–2 с; сам он обновляет вход не дольше 30 с
        for _ in 0..<20 {
            if tryLock(paths[0]) {
                if tryLock(paths[1]) { acquired = true; break }
                try? fm.removeItem(at: paths[0])
            }
            try await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...2_000_000_000))
        }
        guard acquired else { throw RefreshError.busy }
        // пока держим — трогаем, чтобы Claude Code не счёл блокировку брошенной
        let keepAlive = Task.detached {
            while true {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                for p in paths { try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: p.path) }
            }
        }
        defer {
            keepAlive.cancel()
            for p in paths.reversed() { try? fm.removeItem(at: p) }
        }
        return try await body()
    }

    private static func requestRefresh(_ c: Credentials) async throws -> Credentials {
        guard !c.refreshToken.isEmpty else { throw RefreshError.expired }
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": c.refreshToken, "client_id": clientID]
        if !c.scopes.isEmpty { body["scope"] = c.scopes.joined(separator: " ") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200, let access = json["access_token"] as? String else {
            if (400..<500).contains(status) { throw RefreshError.expired }
            throw RefreshError.network(L("Не удалось обновить вход (HTTP %@)", String(status)))
        }
        var oauth = c.oauth
        oauth["accessToken"] = access
        if let r = json["refresh_token"] as? String { oauth["refreshToken"] = r }
        if let e = (json["expires_in"] as? NSNumber)?.doubleValue {
            oauth["expiresAt"] = Int64((Date().timeIntervalSince1970 + e) * 1000)
        }
        var updated = c
        updated.json["claudeAiOauth"] = oauth
        // старый ключ обновления уже недействителен: не записали новый — вход потеряют все
        if !write(updated) { _ = write(updated) }
        return updated
    }
}
