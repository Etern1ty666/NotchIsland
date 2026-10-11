import SwiftUI
import AppKit

/// Статистика в строке меню: шкала, значок и значение на тёмной «таблетке»; у батареи — своя
struct MenuBarStat: View {
    let stat: Stat
    @ObservedObject var stats: SystemStats

    var body: some View {
        Group {
            if stat == .battery { battery } else { gauged }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Theme.menuBarPill))
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.3), value: stats.color(stat))
    }

    var gauged: some View {
        let g = stats.gauge(stat)
        return HStack(spacing: 5) {
            GaugeView(gauge: g, color: stats.color(stat))
                .frame(width: 32, height: g.isBar ? 5 : 12)
            HStack(spacing: 2) {
                Image(systemName: stats.icon(stat))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                value
            }
        }
    }

    @ViewBuilder var value: some View {
        switch stat {
        case .cpu: percentText(stats.cpu, size: 12)
        case .memory: percentText(stats.memFraction, size: 12, warn: false)
        case .disk: percentText(stats.diskUsedFraction, size: 12, warn: false)
        case .battery: EmptyView()
        case .network:
            // две строчки мелко: отдача сверху, загрузка снизу. Колонки: стрелки, числа по правому
            // краю, единицы по левому — всё на одном уровне, как бы ни менялись цифры
            let up = bytesParts(stats.netOut), down = bytesParts(stats.netIn)
            Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: -1) {
                GridRow {
                    Text("↑")
                    Text(up.number).gridColumnAlignment(.trailing)
                    Text(up.unit + "/с")
                }
                GridRow {
                    Text("↓")
                    Text(down.number)
                    Text(down.unit + "/с")
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.white)
            .fixedSize()
        }
    }

    /// Батарейка, залитая по заряду, с процентами на ней (и молнией при зарядке); рядом — сколько осталось
    var battery: some View {
        let b = stats.battery
        return HStack(spacing: 5) {
            BatteryGlyph(level: b?.level ?? 0, charging: b?.charging ?? false, color: stats.color(.battery))
                .frame(width: 34, height: 14)
            if let m = b?.minutesLeft, b?.charging == true || b?.onAC == false {
                Text(shortDuration(minutes: m))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
    }
}

/// Батарейка без рамки, как у macOS: полупрозрачный корпус, светлая заливка по заряду (зелёная при
/// зарядке, жёлтая и красная при низком заряде), проценты прямо на ней. Цифры над заливкой — тёмные,
/// над пустой частью — светлые
struct BatteryGlyph: View {
    let level: Double
    let charging: Bool
    /// Цвет заряда из статистики: им красим заливку при зарядке и низком заряде
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        HStack(spacing: 1.5) {
            GeometryReader { g in
                let fill = g.size.width * CGFloat(min(max(level, 0), 1))
                ZStack(alignment: .leading) {
                    shape.fill(Color.white.opacity(0.35))
                    Rectangle().fill(fillColor).frame(width: fill)
                    label.foregroundStyle(Color.white)
                    label.foregroundStyle(Color.black.opacity(0.85))
                        .mask(alignment: .leading) { Rectangle().frame(width: fill) }
                }
                .clipShape(shape)
            }
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.35))
                .frame(width: 2, height: 5)
        }
    }

    var fillColor: Color {
        if charging || level >= 0.2 { return charging ? Theme.ok : Color.white }
        return color
    }

    var label: some View {
        HStack(spacing: 0.5) {
            if charging { Image(systemName: "bolt.fill").font(.system(size: 7, weight: .black)) }
            Text("\(Int((level * 100).rounded()))")
                .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Лимит подписки Claude в строке меню: слева в две строки — какое окно («5 ч» или «Нед») и сколько
/// до сброса, дальше шкала расхода, значок и проценты
struct MenuBarClaude: View {
    let widget: ClaudeWidget
    @ObservedObject var usage: ClaudeUsage

    var body: some View {
        let w = usage.window(widget)
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: -1) {
                Text(widget.menuBarLabel)
                Text(resetShort(w))
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.55))
            GaugeView(gauge: .bar(w?.spent ?? 0), color: claudeColor(w))
                .frame(width: 24, height: 5)
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
            if let w {
                percentText(w.spent, size: 12, warn: false, color: claudeNumberColor(w))
            } else {
                Text("—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Theme.menuBarPill))
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.3), value: claudeColor(w))
    }

    /// Сколько до сброса: «2ч 10м», «3д 4ч»
    func resetShort(_ w: UsageWindow?) -> String {
        guard let w else { return "нет данных" }
        guard let reset = w.resetsAt else { return "не начато" }
        if w.isReset { return "сейчас" }
        return shortDuration(minutes: Int((reset.timeIntervalSinceNow / 60).rounded(.up)))
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
