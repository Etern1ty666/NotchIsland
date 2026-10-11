import Foundation

/// Окна лимитов подписки Claude, которые можно закрепить в строке меню
enum ClaudeWidget: String, CaseIterable, Identifiable {
    case session, week
    var id: String { rawValue }
    var title: String {
        switch self {
        case .session: return L("Сессия · 5 ч")
        case .week: return L("Неделя")
        }
    }
    /// Какое это окно — в настройках
    var short: String {
        switch self {
        case .session: return L("5 часов")
        case .week: return L("неделя")
        }
    }
    /// То же коротко — в строке меню
    var menuBarLabel: String {
        switch self {
        case .session: return L("5 ч")
        case .week: return L("Нед")
        }
    }
}

/// Окно лимита подписки Claude Pro/Max: сколько процентов израсходовано и когда обнулится
struct UsageWindow: Equatable {
    var used: Double        // 0...1
    var resetsAt: Date?     // nil — окно ещё не началось (в нём ничего не потрачено)

    /// Окно уже обнулилось, а свежих цифр ещё нет
    var isReset: Bool { resetsAt.map { $0 <= Date() } ?? false }
    /// Сколько израсходовано сейчас: обнулившееся окно — 0
    var spent: Double { isReset ? 0 : min(max(used, 0), 1) }
}
