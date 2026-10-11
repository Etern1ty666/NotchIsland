import SwiftUI

/// Цвет окна лимита: спокойный, пока израсходовано немного; без данных — серый
func claudeColor(_ w: UsageWindow?) -> Color {
    guard let w else { return Theme.idle }
    return loadColor(w.spent, calm: 0.6, busy: 0.85)
}

/// Цвет числа: 0% — зелёный, чтобы нетронутый лимит не путался с «не загрузилось»
func claudeNumberColor(_ w: UsageWindow) -> Color? {
    (w.spent * 100).rounded() > 0 ? nil : claudeColor(w)
}

/// Окно лимита подписки: сколько израсходовано, когда обнулится. Без данных — клик ведёт в настройки
struct ClaudeWindowCard: View {
    @ObservedObject var usage: ClaudeUsage
    let widget: ClaudeWidget
    let pinned: Bool
    let onPin: () -> Void
    let openSettings: () -> Void

    var window: UsageWindow? { usage.window(widget) }

    var body: some View {
        let spent = window?.spent ?? 0
        // шкала заполняется по мере расхода
        CardLayout(icon: "sparkles", title: widget.title, color: claudeColor(window),
                   gauge: .bar(spent), detail: detail, pinned: pinned, onPin: onPin,
                   onTap: window == nil ? openSettings : nil) {
            if let window {
                Text("\(percentText(window.spent, size: 20, warn: false, color: claudeNumberColor(window)))\(Text(" " + L("израсходовано")).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.45)))")
            } else {
                valueText("—")
            }
        }
    }

    var detail: String {
        guard let window else {
            if !usage.accountEnabled { return L("Аккаунт отключён — см. настройки") }
            if let e = usage.apiError { return e }
            return usage.loggedIn ? L("Загружаю") : L("Нужен вход в Claude Code — см. настройки")
        }
        return resetText(window.resetsAt).capitalizedFirst
    }
}
