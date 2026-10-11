import Foundation

func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

/// 9,8 ГБ. Память считаем в двоичных единицах (как «Мониторинг системы»), диск и сеть — в десятичных (как Finder)
func formatBytes(_ b: Double, binary: Bool = false) -> String {
    let k: Double = binary ? 1024 : 1000
    let units = ["Б", "КБ", "МБ", "ГБ", "ТБ"]
    var v = max(0, b), i = 0
    while v >= k && i < units.count - 1 { v /= k; i += 1 }
    let s = i >= 2 && v < 100 ? String(format: "%.1f", v) : String(format: "%.0f", v)
    return s.replacingOccurrences(of: ".", with: ",") + " " + units[i]
}

func formatSpeed(_ b: Double) -> String { formatBytes(b) + "/с" }

/// 25 мин, 1 ч 12 мин
func formatMinutes(_ m: Int) -> String {
    m < 60 ? "\(m) мин" : "\(m / 60) ч" + (m % 60 > 0 ? " \(m % 60) мин" : "")
}

func relativeTime(_ d: Date) -> String {
    let s = Int(Date().timeIntervalSince(d))
    if s < 10 { return "сейчас" }
    if s < 60 { return "\(s) с" }
    if s < 3600 { return "\(s / 60) мин" }
    if s < 86400 { return "\(s / 3600) ч" }
    return "\(s / 86400) д"
}

/// 1 запись, 2 записи, 5 записей
func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let n10 = n % 10, n100 = n % 100
    if n10 == 1 && n100 != 11 { return one }
    if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
    return many
}

/// ISO 8601 с долями секунды любой длины («2026-10-11T04:59:59.943648+00:00») и без них
func parseISODate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return f.date(from: trimmed)
}

/// «через 2 ч 10 мин» / «в пн 14:00»
func resetText(_ d: Date?) -> String {
    guard let d else { return "окно ещё не началось" }
    let m = Int((d.timeIntervalSinceNow / 60).rounded(.up))
    if m <= 0 { return "окно обновилось" }
    if m < 24 * 60 { return "сброс через \(formatMinutes(m))" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = "EE HH:mm"
    return "сброс в \(f.string(from: d).lowercased())"
}

extension String {
    /// «сброс через 2 ч» → «Сброс через 2 ч»
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// «обновлено 5 мин назад»
func agoText(_ d: Date) -> String {
    let m = Int(-d.timeIntervalSinceNow / 60)
    if m < 1 { return "только что" }
    if m < 60 { return "\(m) мин назад" }
    if m < 24 * 60 { return "\(m / 60) ч назад" }
    return "\(m / (24 * 60)) д назад"
}
