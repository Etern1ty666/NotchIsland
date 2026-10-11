import SwiftUI
import AppKit

/// Страница настроек справа от zzz: срок хранения буфера и откуда брать лимиты подписки Claude
struct SettingsView: View {
    @ObservedObject var usage: ClaudeUsage
    @ObservedObject var clip: ClipboardStore
    @State private var message: String?
    @State private var confirmReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "list.clipboard", title: "Буфер обмена")
            SettingsRow(icon: "clock.arrow.circlepath", title: "Хранить незакреплённое",
                        subtitle: "Закреплённое хранится всегда") {
                SegmentPicker(options: ClipRetention.allCases.map { ($0, $0.title) }, selection: $clip.retention)
            }

            SectionHeader(icon: "sparkles", title: "Лимиты подписки Claude")
                .padding(.top, 6)
            // Источник 1: вход Claude Code — обновляется сам, учитывает и приложение, и браузер
            SettingsRow(icon: loginIcon, iconColor: loginColor, title: "Аккаунт Claude", subtitle: loginStatus) {
                loginButtons
            }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(1)
            }

            // Источник 2: строка состояния Claude Code — официально, но только для терминала
            SettingsRow(icon: "terminal", title: "Лимиты из терминала Claude Code", subtitle: lineStatus) {
                connectionButton
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { usage.refreshConnection() }
    }

    @ViewBuilder var connectionButton: some View {
        switch usage.connection {
        case .ours:
            PillButton(title: "Отключить", destructive: true) { message = usage.disconnect() }
        case .none:
            PillButton(title: "Подключить") { message = usage.connect() }
        case .other:
            PillButton(title: confirmReplace ? "Точно заменить?" : "Заменить", destructive: confirmReplace) {
                if confirmReplace { message = usage.connect(); confirmReplace = false }
                else { confirmReplace = true }
            }
        }
    }

    @ViewBuilder var loginButtons: some View {
        if usage.loggedIn {
            PillButton(title: "Проверить сейчас") { usage.fetchNow() }
        } else {
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

    var loginStatus: String {
        if !usage.loggedIn {
            switch usage.login {
            case .idle: return "Вход не выполнен"
            case .waiting: return "Жду вход в браузере…"
            case .failed(let m): return m
            }
        }
        if let e = usage.apiError { return e }
        return usage.updatedAt.map { "Вход выполнен · обновлено " + agoText($0) } ?? "Проверяю…"
    }
    var loginIcon: String {
        !usage.loggedIn ? "person.crop.circle.badge.questionmark"
            : (usage.apiError == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
    }
    var loginColor: Color {
        !usage.loggedIn ? Color.white.opacity(0.5) : (usage.apiError == nil ? Theme.ok : Theme.critical)
    }
    var lineStatus: String {
        switch usage.connection {
        case .ours: return "Подключено"
        case .none: return "Не подключено"
        case .other: return "Занято другой строкой состояния"
        }
    }
}

/// Строка настроек: значок, название с пояснением и элементы управления справа
struct SettingsRow<Accessory: View>: View {
    let icon: String
    var iconColor = Color.white.opacity(0.5)
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(iconColor).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45)).lineLimit(1)
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .cardBackground()
    }
}
