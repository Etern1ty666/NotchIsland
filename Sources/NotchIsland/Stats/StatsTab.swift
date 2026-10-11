import SwiftUI

/// Два раздела: система и лимиты подписки Claude. Клик по карточке — показывать ли её в строке меню.
/// Остров одной высоты на всех вкладках, поэтому раздел прокручивается
struct StatsTab: View {
    @ObservedObject var stats: SystemStats
    @ObservedObject var settings: StatsSettings
    @ObservedObject var usage: ClaudeUsage
    let openSettings: () -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        FadingScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(icon: "desktopcomputer", title: "Система")
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(stats.available) { s in
                        StatCard(stat: s, stats: stats, pinned: settings.pinned.contains(s)) { settings.toggle(s) }
                    }
                }
                HStack(spacing: 6) {
                    SectionHeader(icon: "sparkles", title: "Claude")
                    if let d = usage.updatedAt {
                        Text(L("обновлено %@", agoText(d)))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    RefreshButton(busy: usage.fetching) { usage.refresh() }
                        .padding(.vertical, -3)   // строка не выше обычного заголовка
                    Spacer()
                }
                .padding(.top, 6)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ClaudeWidget.allCases) { w in
                        ClaudeWindowCard(usage: usage, widget: w, pinned: settings.pinnedClaude.contains(w),
                                         onPin: { settings.toggle(w) }, openSettings: openSettings)
                    }
                }
            }
        }
    }
}

struct StatCard: View {
    let stat: Stat
    @ObservedObject var stats: SystemStats
    let pinned: Bool
    let onPin: () -> Void

    var body: some View {
        CardLayout(icon: stats.icon(stat), title: stat.title, color: stats.color(stat),
                   gauge: stats.gauge(stat), detail: detail, pinned: pinned, onPin: onPin) {
            value
        }
    }

    @ViewBuilder var value: some View {
        switch stat {
        case .cpu: percentText(stats.cpu, size: 20)
        case .memory: valueText(formatBytes(stats.memUsed, binary: true), " " + L("из %@", formatBytes(stats.memTotal, binary: true)))
        case .network: valueText("↓ " + formatSpeed(stats.netIn))
        case .disk: valueText(formatBytes(stats.diskFree), " " + L("свободно"))
        case .battery: percentText(stats.battery?.level ?? 0, size: 20, warn: false)
        }
    }

    var detail: String {
        switch stat {
        case .cpu: return L("Пользователь %@ · система %@", pct(stats.cpuUser), pct(stats.cpuSystem))
        case .memory: return L("Занято %@", pct(stats.memFraction))
        case .network: return "↑ " + formatSpeed(stats.netOut)
        case .disk: return L("Занято %@ из %@", pct(stats.diskUsedFraction), formatBytes(stats.diskTotal))
        case .battery: return stats.batteryState
        }
    }
}
