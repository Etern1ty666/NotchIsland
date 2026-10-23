import SwiftUI

/// Что нового — по версиям, свежие сверху. После обновления внизу острова плашка «Что нового в версии …»:
/// клик открывает этот список страницей острова (как настройки), крестик прячет плашку до следующего обновления.
/// Перед выпуском версии сюда дописывают её пункты, а в Translations.strings — их переводы
enum WhatsNew {
    struct Release: Identifiable {
        let version: String
        let items: [String]
        var id: String { version }
    }

    static let releases: [Release] = [
        Release(version: "1.29", items: [
            "После обновления внизу острова — «Что нового»: клик открывает список изменений, крестик прячет",
            "Выбранные записи: действия с ними — вверху острова вместо вкладок, внизу — сколько выбрано",
            "Текст и файлы вместе не вставить, поэтому при выборе неподходящие записи становятся серыми",
        ]),
        Release(version: "1.28", items: [
            "⌘-клик по записям буфера выбирает несколько: их можно скопировать вместе или удалить, Esc снимает выбор",
        ]),
    ]

    static let accent = Color(red: 0.62, green: 0.66, blue: 1)

    /// Свежие изменения, какие есть у этой версии: у исправлений вроде 1.29.1 своих нет — показываем 1.29
    static var latest: Release? {
        releases.first { !isNewer($0.version, than: Updater.currentVersion) }
    }

    /// При запуске: обновились ли с прошлого раза и есть ли что рассказать. Новому пользователю — нет:
    /// запоминаем текущую версию как уже виденную
    static func checkOnLaunch() -> Bool {
        let d = UserDefaults.standard
        guard let seen = d.string(forKey: DefaultsKey.whatsNewSeen) else {
            // до 1.29 виденную версию не запоминали. Остров уже раскрывали — значит, это обновление, а не установка
            if d.string(forKey: DefaultsKey.islandHintVersion) != nil { return latest != nil }
            markSeen()
            return false
        }
        return latest.map { isNewer($0.version, than: seen) } ?? false
    }

    static func markSeen() {
        UserDefaults.standard.set(Updater.currentVersion, forKey: DefaultsKey.whatsNewSeen)
    }

    /// «1.29» новее «1.28», «1.100» новее «1.99»
    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}

/// Плашка «Что нового» внизу острова
enum WhatsNewBarState {
    case none
    case shown
    /// Спрятали крестиком или открыли список: плашки нет, но остров держит её высоту, пока не свернётся.
    /// Стань он сразу ниже, курсор на плашке оказался бы снаружи и остров свернулся бы сам
    case closed
}

/// «✨ Что нового в версии 1.29  ×» — внизу острова после обновления
struct WhatsNewBar: View {
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            GreenButton(icon: "sparkles", title: L("Что нового в версии %@", WhatsNew.latest?.version ?? Updater.currentVersion),
                        help: "Что изменилось в этой версии", color: WhatsNew.accent, action: open)
            CircleIconButton(systemName: "xmark", help: "Спрятать", action: close)
        }
    }
}

/// Список изменений по версиям — страница острова вместо вкладки. Уходит, когда выбирают вкладку или остров сворачивается
struct WhatsNewView: View {
    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(WhatsNew.releases) { release in
                    SectionHeader(icon: "sparkles", title: L("Версия %@", release.version))
                        .padding(.top, release.id == WhatsNew.releases.first?.id ? 0 : 6)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(release.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 9) {
                                Circle().fill(WhatsNew.accent).frame(width: 5, height: 5).padding(.top, 6)
                                Text(L(item))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()
                }
            }
        }
    }
}
