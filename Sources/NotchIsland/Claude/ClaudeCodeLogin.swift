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

    enum RefreshError: Error { case expired, network(String) }

    /// Обновляем вход так же, как Claude Code, и записываем новые токены обратно в связку ключей —
    /// чтобы и сам Claude Code продолжил работать
    static func refresh(_ c: Credentials) async throws -> Credentials {
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
            throw RefreshError.network("Не удалось обновить вход (HTTP \(status))")
        }
        var oauth = c.oauth
        oauth["accessToken"] = access
        if let r = json["refresh_token"] as? String { oauth["refreshToken"] = r }
        if let e = (json["expires_in"] as? NSNumber)?.doubleValue {
            oauth["expiresAt"] = Int64((Date().timeIntervalSince1970 + e) * 1000)
        }
        var updated = c
        updated.json["claudeAiOauth"] = oauth
        _ = write(updated)
        return updated
    }
}
