import SwiftUI
import AppKit

/// Статистика в строке меню: шкала, значок и значение на тёмной «таблетке»
struct MenuBarStat: View {
    let stat: Stat
    @ObservedObject var stats: SystemStats

    var body: some View {
        let g = stats.gauge(stat)
        HStack(spacing: 5) {
            GaugeView(gauge: g, color: stats.color(stat))
                .frame(width: 32, height: g.isBar ? 5 : 12)
            HStack(spacing: 2) {
                Image(systemName: stats.icon(stat))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                value
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Theme.menuBarPill))
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.3), value: stats.color(stat))
    }

    @ViewBuilder var value: some View {
        switch stat {
        case .cpu: percentText(stats.cpu, size: 12)
        case .memory: percentText(stats.memFraction, size: 12, warn: false)
        case .disk: percentText(stats.diskUsedFraction, size: 12, warn: false)
        case .battery: percentText(stats.battery?.level ?? 0, size: 12, warn: false)
        case .network:
            // две строчки мелко: отдача сверху, загрузка снизу
            VStack(alignment: .trailing, spacing: -1) {
                Text("↑ " + formatSpeed(stats.netOut))
                Text("↓ " + formatSpeed(stats.netIn))
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.white)
        }
    }
}

/// Лимит подписки Claude в строке меню: шкала расхода, значок с подписью окна и проценты
struct MenuBarClaude: View {
    let widget: ClaudeWidget
    @ObservedObject var usage: ClaudeUsage

    var body: some View {
        let w = usage.window(widget)
        HStack(spacing: 5) {
            GaugeView(gauge: .bar(w?.spent ?? 0), color: claudeColor(w))
                .frame(width: 32, height: 5)
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                Text(widget.short)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                if let w {
                    percentText(w.spent, size: 12, warn: false, color: claudeNumberColor(w))
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Theme.menuBarPill))
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.3), value: claudeColor(w))
    }
}

/// Отдельный значок «Держать экран включенным» в строке меню — виден, пока режим включён:
/// оранжевый, а если выбран срок — с обратным отсчётом
struct MenuBarAwake: View {
    @ObservedObject var awake: KeepAwake

    var body: some View {
        // выключен — пусто: значок сжат в ноль, но держит место в строке меню
        if awake.active { pill }
    }

    var pill: some View {
        HStack(spacing: 4) {
            SleepIcon(slashed: true, size: 11, background: Theme.menuBarPill)
            // выбран срок — рядом обратный отсчёт; ширина под две цифры, чтобы соседи не прыгали
            if let until = awake.until {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ZStack(alignment: .leading) {
                        ForEach(["88ч", "88м", "88с"], id: \.self) { Text($0).hidden() }
                        Text(KeepAwake.shortRemaining(until: until, now: context.date))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
        }
        .foregroundStyle(Theme.awake)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(Theme.menuBarPill))
        .environment(\.colorScheme, .dark)
    }
}

/// SwiftUI внутри кнопки строки меню, но клики проходят к самой кнопке — она открывает меню
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
