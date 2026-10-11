import SwiftUI
import AppKit

/// Настройки (шестерёнка справа от zzz): буфер, строка меню, экран, Claude, приложение.
/// Целиком в остров не помещаются — прокручиваются
struct SettingsView: View {
    @ObservedObject var usage: ClaudeUsage
    @ObservedObject var clip: ClipboardStore
    /// Не @ObservedObject: замеры раз в 2 секунды здесь не нужны — только есть ли батарея
    let stats: SystemStats
    @ObservedObject var statsSettings: StatsSettings
    @ObservedObject var awake: KeepAwake
    @ObservedObject var updater: Updater
    @ObservedObject var loginItem = LoginItem.shared

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(icon: "list.clipboard", title: "Буфер обмена")
                SettingsRow(icon: "clock.arrow.circlepath", title: "Хранить историю") {
                    SegmentPicker(options: ClipRetention.allCases.map { ($0, $0.title) }, selection: $clip.retention)
                }

                section("Строка меню", icon: "menubar.rectangle")
                menuBarItems

                section("Экран", icon: "display")
                SettingsRow(icon: "zzz", iconColor: awake.active ? Theme.awake : Color.white.opacity(0.5),
                            title: KeepAwake.title, help: awake.active ? awake.statusText : nil) {
                    SegmentPicker(options: awakeOptions, selection: awakeSelection)
                }

                section("Claude", icon: "sparkles")
                // вход Claude Code: лимиты обновляются сами и учитывают и приложение, и браузер
                SettingsRow(icon: loginIcon, iconColor: loginColor, title: "Аккаунт Claude", help: loginStatus) {
                    loginButtons
                }

                section("Приложение", icon: "macwindow")
                SettingsRow(icon: "power", title: "Запускать при входе",
                            help: loginItem.available ? nil : "Работает, когда приложение лежит в «Программах»") {
                    SegmentPicker(options: [(false, "Выкл"), (true, "Вкл")],
                                  selection: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
                        .disabled(!loginItem.available)
                        .opacity(loginItem.available ? 1 : 0.5)
                }
                SettingsRow(icon: "arrow.down.circle", title: "Версия \(Updater.currentVersion)") {
                    if updater.availableVersion != nil {
                        PillButton(title: "Обновить") { updater.update() }
                    } else {
                        PillButton(title: "Проверить обновления") { updater.checkForUpdates() }
                    }
                }
            }
        }
        .onAppear { loginItem.refresh() }
    }

    func section(_ title: String, icon: String) -> some View {
        SectionHeader(icon: icon, title: title).padding(.top, 6)
    }

    // MARK: Строка меню

    /// Какие значки показывать в строке меню — «таблетками», нажатие включает и выключает
    var menuBarItems: some View {
        FlowLayout(spacing: 6) {
            ForEach(stats.available) { s in
                ChipToggle(title: s.title, isOn: statsSettings.pinned.contains(s)) { statsSettings.toggle(s) }
            }
            ForEach(ClaudeWidget.allCases) { w in
                ChipToggle(title: "Claude · " + w.title, isOn: statsSettings.pinnedClaude.contains(w)) {
                    statsSettings.toggle(w)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: Экран

    /// «Выкл» и сроки: 30 мин, 1 ч, 3 ч, 8 ч, Всегда
    var awakeOptions: [(Int, String)] {
        [(0, "Выкл")] + KeepAwake.options.enumerated().map { i, o in (i + 1, o.minutes.map(formatMinutes) ?? "Всегда") }
    }

    var awakeSelection: Binding<Int> {
        Binding(
            get: { awake.active ? (awake.chosen.map { $0 + 1 } ?? KeepAwake.options.count) : 0 },
            set: { $0 == 0 ? awake.disable() : awake.choose($0 - 1) })
    }

    // MARK: Claude

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
/// Состояние (вход выполнен, ошибка) — в подсказке при наведении
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
            // кнопки и переключатели — всегда своей полной ширины, сжимается название
            accessory().fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .cardBackground()
        .help(help ?? "")
    }
}

/// «Таблетка»-переключатель: включена — светлая с галочкой
struct ChipToggle: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(isOn ? 1 : (hover ? 0.85 : 0.55)))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(isOn ? 0.2 : (hover ? 0.1 : 0.06))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
