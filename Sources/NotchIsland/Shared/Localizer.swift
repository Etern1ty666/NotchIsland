import SwiftUI
import AppKit

/// Языки приложения. Русский — исходный: строки в коде написаны по-русски и сами служат ключами.
/// Для других языков в Resources/<язык>.lproj/Translations.strings лежат пары
/// «"русская строка" = "перевод";» — чтобы добавить язык, достаточно положить такой файл
/// и дописать язык в `supported`. Строки с подстановкой — форматы: «Обновить до %@».
///
/// Язык берётся из системы (первый из предпочитаемых, на который есть перевод; иначе английский)
/// и меняется на лету: стоит сменить язык в системе — остров, значки и меню перерисуются сразу.
/// Таблица называется не Localizable, чтобы SwiftUI не переводил литералы сам при запуске
final class Localizer: ObservableObject, @unchecked Sendable {
    static let shared = Localizer()
    /// Языки с переводом; первый — исходный, для него таблица не нужна
    static let supported = ["ru", "en"]
    static let fallback = "en"

    @Published private(set) var language: String
    private var table: [String: String] = [:]
    /// Строки читают и не с главного потока (вход в Claude) — таблицу меняем под замком
    private let lock = NSLock()

    private init() {
        language = Self.systemLanguage()
        table = Self.loadTable(language)
        // язык сменили в «Язык и регион» — системное уведомление; регион — уведомление о локали
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleLanguagePreferencesChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    /// Перечитать язык системы; заодно зовётся при раскрытии острова и открытии меню — на всякий случай
    func refresh() {
        let lang = Self.systemLanguage()
        guard lang != language else { return }
        let new = Self.loadTable(lang)
        lock.lock()
        table = new
        lock.unlock()
        language = lang
    }

    func string(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return table[key] ?? key
    }

    var isRussian: Bool { language == "ru" }
    /// Для дат и чисел — под язык интерфейса
    var locale: Locale { Locale(identifier: isRussian ? "ru_RU" : "en_US") }

    /// Первый из предпочитаемых языков системы (или этого приложения, если язык задан для него
    /// отдельно), на который есть перевод
    static func systemLanguage() -> String {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        for id in preferred {
            let code = Locale(identifier: id).language.languageCode?.identifier ?? String(id.prefix(2))
            if supported.contains(code) { return code }
        }
        return fallback
    }

    private static func loadTable(_ language: String) -> [String: String] {
        guard language != supported[0],
              let path = Bundle.main.path(forResource: "Translations", ofType: "strings",
                                          inDirectory: nil, forLocalization: language),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else { return [:] }
        return dict
    }
}

/// Строка интерфейса на языке системы: L("Скопировано")
func L(_ key: String) -> String { Localizer.shared.string(key) }

/// Строка с подстановкой: L("Обновить до %@", version)
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.string(key), arguments: args)
}

/// «3 файла» / «3 files»: русские формы — одна, несколько, много; английские — одна и много
func countText(_ n: Int, ru: (one: String, few: String, many: String), en: (one: String, many: String)) -> String {
    guard Localizer.shared.isRussian else { return "\(n) \(n == 1 ? en.one : en.many)" }
    let n10 = n % 10, n100 = n % 100
    if n10 == 1 && n100 != 11 { return "\(n) \(ru.one)" }
    if (2...4).contains(n10) && !(12...14).contains(n100) { return "\(n) \(ru.few)" }
    return "\(n) \(ru.many)"
}

/// Корень окна на языке системы: при смене языка всё внутри строится заново
struct LocalizedRoot<Content: View>: View {
    @ObservedObject var localizer = Localizer.shared
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .id(localizer.language)
            .environment(\.locale, localizer.locale)
    }
}
