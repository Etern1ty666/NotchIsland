import Foundation

func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

/// 9,8 ГБ. Память считаем в двоичных единицах (как «Мониторинг системы»), диск и сеть — в десятичных (как Finder)
func formatBytes(_ b: Double, binary: Bool = false) -> String {
    let p = bytesParts(b, binary: binary)
    return p.number + " " + p.unit
}

/// Число и единица отдельно — чтобы выровнять их колонками: («9,8», «ГБ»).
/// Единицы и десятичный знак — по языку интерфейса
func bytesParts(_ b: Double, binary: Bool = false) -> (number: String, unit: String) {
    let k: Double = binary ? 1024 : 1000
    let units = ["Б", "КБ", "МБ", "ГБ", "ТБ"].map(L)
    var v = max(0, b), i = 0
    while v >= k && i < units.count - 1 { v /= k; i += 1 }
    let s = i >= 2 && v < 100 ? String(format: "%.1f", v) : String(format: "%.0f", v)
    return (Localizer.shared.isRussian ? s.replacingOccurrences(of: ".", with: ",") : s, units[i])
}

func formatSpeed(_ b: Double) -> String { formatBytes(b) + L("/с") }

/// Коротко для строки меню: «45м», «2ч 10м», «3д 4ч»
func shortDuration(minutes m: Int) -> String {
    let m = max(0, m)
    let min = L("м"), hour = L("ч"), day = L("д")
    if m < 60 { return "\(m)\(min)" }
    if m < 24 * 60 { return "\(m / 60)\(hour)" + (m % 60 > 0 ? " \(m % 60)\(min)" : "") }
    let h = (m % (24 * 60)) / 60
    return "\(m / (24 * 60))\(day)" + (h > 0 ? " \(h)\(hour)" : "")
}

/// 25 мин, 1 ч 12 мин
func formatMinutes(_ m: Int) -> String {
    let min = L("мин"), hour = L("ч")
    return m < 60 ? "\(m) \(min)" : "\(m / 60) \(hour)" + (m % 60 > 0 ? " \(m % 60) \(min)" : "")
}

/// Сколько прошло: «сейчас», «40 с», «5 мин», «2 ч», «3 д»
func relativeTime(_ d: Date) -> String {
    let s = Int(Date().timeIntervalSince(d))
    if s < 10 { return L("сейчас") }
    if s < 60 { return "\(s) \(L("с"))" }
    if s < 3600 { return "\(s / 60) \(L("мин"))" }
    if s < 86400 { return "\(s / 3600) \(L("ч"))" }
    return "\(s / 86400) \(L("д"))"
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

/// «сброс через 2 ч 10 мин» / «сброс в пн 14:00»
func resetText(_ d: Date?) -> String {
    guard let d else { return L("окно ещё не началось") }
    let m = Int((d.timeIntervalSinceNow / 60).rounded(.up))
    if m <= 0 { return L("окно обновилось") }
    if m < 24 * 60 { return L("сброс через %@", formatMinutes(m)) }
    let f = DateFormatter()
    f.locale = Localizer.shared.locale
    f.dateFormat = "EE HH:mm"
    return L("сброс в %@", f.string(from: d).lowercased())
}

extension String {
    /// «сброс через 2 ч» → «Сброс через 2 ч»
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// «обновлено 5 мин назад»
func agoText(_ d: Date) -> String {
    let m = Int(-d.timeIntervalSinceNow / 60)
    if m < 1 { return L("только что") }
    if m < 60 { return L("%@ мин назад", String(m)) }
    if m < 24 * 60 { return L("%@ ч назад", String(m / 60)) }
    return L("%@ д назад", String(m / (24 * 60)))
}
