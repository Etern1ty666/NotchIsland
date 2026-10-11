import SwiftUI
import AppKit

/// Страница настроек справа от zzz: срок хранения буфера и аккаунт Claude для лимитов подписки
struct SettingsView: View {
    @ObservedObject var usage: ClaudeUsage
    @ObservedObject var clip: ClipboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "list.clipboard", title: "Буфер обмена")
            SettingsRow(icon: "clock.arrow.circlepath", title: "Хранить историю") {
                SegmentPicker(options: ClipRetention.allCases.map { ($0, $0.title) }, selection: $clip.retention)
            }

            SectionHeader(icon: "sparkles", title: "Claude")
                .padding(.top, 6)
            // вход Claude Code: лимиты обновляются сами и учитывают и приложение, и браузер
            SettingsRow(icon: loginIcon, iconColor: loginColor, title: "Аккаунт Claude", help: loginStatus) {
                loginButtons
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder var loginButtons: some View {
        if !usage.accountEnabled {
            PillButton(title: "Подключить") { usage.setAccountEnabled(true) }
        } else if usage.loggedIn && !usage.authLost {
            PillButton(title: "Отключить", destructive: true) { usage.setAccountEnabled(false) }
        } else {
            // входа нет или он пропал — войти (заново)
            switch usage.login {
            case .idle:
                PillButton(title: "Войти") { usage.startLogin() }
            case .waiting(let url):
                if let url {
                    PillButton(title: "Открыть ссылку") { NSWorkspace.shared.open(url) }
                }
                PillButton(title: "Отмена", destructive: true) { usage.cancelLogin() }
            case .failed:
                PillButton(title: "Открыть в Терминале") { usage.loginInTerminal() }
                PillButton(title: "Ещё раз") { usage.startLogin() }
            }
        }
    }

    /// Состояние — в подсказке при наведении на строку
    var loginStatus: String {
        if !usage.accountEnabled { return "Отключено — лимиты не запрашиваются" }
        if !usage.loggedIn || usage.authLost {
            switch usage.login {
            case .idle: return usage.authLost ? (usage.apiError ?? "Вход пропал — войди заново") : "Вход не выполнен"
            case .waiting: return "Жду вход в браузере…"
            case .failed(let m): return m
            }
        }
        if let e = usage.apiError { return e }
        return usage.updatedAt.map { "Вход выполнен · обновлено " + agoText($0) } ?? "Проверяю…"
    }
    /// Красный — только когда вход пропал; временные сбои сервера и сети значок не трогают
    var loginIcon: String {
        if !usage.accountEnabled { return "person.crop.circle" }
        if usage.authLost { return "exclamationmark.circle.fill" }
        return usage.loggedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark"
    }
    var loginColor: Color {
        if !usage.accountEnabled { return Color.white.opacity(0.5) }
        if usage.authLost { return Theme.critical }
        return usage.loggedIn ? Theme.ok : Color.white.opacity(0.5)
    }
}

/// Строка настроек: значок, название и элементы управления справа.
/// Состояние (вход выполнен, ошибка, подключено) — в подсказке при наведении
struct SettingsRow<Accessory: View>: View {
    let icon: String
    var iconColor = Color.white.opacity(0.5)
    let title: String
    var help: String?
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(iconColor).frame(width: 18)
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .cardBackground()
        .help(help ?? "")
    }
}
