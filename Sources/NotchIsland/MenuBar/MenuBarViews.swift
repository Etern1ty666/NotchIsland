import SwiftUI
import AppKit

/// Значки в строке меню — на тёмной «таблетке» (белые) или без неё: тогда цвет под строку меню —
/// белый на тёмной, чёрный на светлой, чтобы на прозрачной строке поверх обоев не сливались
extension View {
    func menuBarPill(_ on: Bool, padding: CGFloat = 8, scheme: ColorScheme) -> some View {
        self.padding(.horizontal, on ? padding : 3)
            .frame(height: 22)
            .background { if on { MenuBarPillBackground() } }
            .environment(\.colorScheme, on ? .dark : scheme)
    }
}

/// «Таблетка» под значком: размытое то, что под строкой меню, притемнённое — читается на любых обоях
struct MenuBarPillBackground: View {
    var body: some View {
        ZStack {
            BehindWindowBlur()
            Theme.menuBarPill.opacity(0.55)
        }
        .clipShape(Capsule())
    }
}

/// Системное размытие того, что под окном (SwiftUI-материалы размывают только содержимое своего окна)
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material = .hudWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Основной цвет значка: на «таблетке» всегда белый, без неё — как текст строки меню
func menuBarInk(pill: Bool, scheme: ColorScheme) -> Color {
    pill || scheme == .dark ? .white : .black
}

/// Статистика в строке меню: шкала, значок и значение; у батареи — своя
struct MenuBarStat: View {
    let stat: Stat
    @ObservedObject var stats: SystemStats
    @ObservedObject var settings: StatsSettings
    /// Оформление строки меню (светлая или тёмная) — macOS сама меняет его под обои
    /// С подложкой или без; nil — как в настройках. Явно — для замера ширины до переключения
    var pill: Bool? = nil
    @Environment(\.colorScheme) private var scheme
    var onPill: Bool { pill ?? settings.menuPill }
    var ink: Color { menuBarInk(pill: onPill, scheme: scheme) }

    var body: some View {
        Group {
            if stat == .battery { battery } else { gauged }
        }
        .menuBarPill(onPill, scheme: scheme)
        .animation(.easeOut(duration: 0.3), value: stats.color(stat))
    }

    var gauged: some View {
        let g = stats.gauge(stat)
        return HStack(spacing: 5) {
            GaugeView(gauge: g, color: stats.color(stat), ink: ink)
                .frame(width: 32, height: g.isBar ? 5 : 12)
            HStack(spacing: 2) {
                Image(systemName: stats.icon(stat))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.75))
                value
            }
        }
    }

    @ViewBuilder var value: some View {
        switch stat {
        case .cpu: percentText(stats.cpu, size: 12, ink: ink)
        case .memory: percentText(stats.memFraction, size: 12, warn: false, ink: ink)
        case .disk: percentText(stats.diskUsedFraction, size: 12, warn: false, ink: ink)
        case .battery: EmptyView()
        case .network:
            // две строчки мелко: отдача сверху, загрузка снизу. Колонки: стрелки, числа по правому
            // краю, единицы по левому — всё на одном уровне, как бы ни менялись цифры
            // колонки — постоянной ширины (под «88,8» и «МБ/с»): ширина значка не скачет, «/с» на одном уровне
            let up = bytesParts(stats.netOut), down = bytesParts(stats.netIn)
            let numberWidest = Localizer.shared.isRussian ? "88,8" : "88.8"
            let unitWidest = ["КБ", "МБ", "ГБ"].map { L($0) + L("/с") }
            Grid(alignment: .trailing, horizontalSpacing: 3, verticalSpacing: -1) {
                GridRow {
                    Text("↑")
                    widest(up.number, [numberWidest])
                    widest(up.unit + L("/с"), unitWidest)
                }
                GridRow {
                    Text("↓")
                    widest(down.number, [numberWidest])
                    widest(down.unit + L("/с"), unitWidest)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(ink)
            .fixedSize()
        }
    }

    /// Текст в рамке ширины самого длинного из образцов, по правому краю
    func widest(_ text: String, _ samples: [String]) -> some View {
        ZStack(alignment: .trailing) {
            ForEach(samples, id: \.self) { Text($0).hidden() }
            Text(text)
        }
    }

    /// Батарейка, залитая по заряду, с процентами на ней (и молнией при зарядке); рядом — сколько
    /// осталось (сразу после переключения — примерно, потом точнее) или вилка — от сети, но не заряжается
    var battery: some View {
        let b = stats.battery
        return HStack(spacing: 5) {
            BatteryGlyph(level: b?.level ?? 0, charging: b?.charging ?? false, color: stats.color(.battery), ink: ink)
                .frame(height: 16)
            if let b {
                if b.state == .charging || b.state == .battery {
                    if let m = b.minutes {
                        Text(shortDuration(minutes: m))
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(ink.opacity(0.85))
                    }
                } else {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.75))
                }
            }
        }
    }
}

/// Батарейка без рамки: полупрозрачный корпус, ярче — заряд (цвета `ink`; зелёный при зарядке, жёлтый
/// и красный при низком заряде), проценты прямо на ней — контрастные, одним цветом: читаются на любой части.
/// Корпус постоянной ширины; шире — только когда подпись в него не влезает (молния и «100» при дозарядке),
/// чтобы цифры не обрезались «…»
struct BatteryGlyph: View {
    let level: Double
    let charging: Bool
    /// Цвет заряда из статистики: им красим заливку при зарядке и низком заряде
    let color: Color
    /// Основной цвет: белая батарейка на тёмной строке меню, чёрная — на светлой
    var ink = Color.white
    var light: Bool { ink == .white }
    /// Обычная ширина корпуса, без контакта справа
    static let bodyWidth: CGFloat = 32.5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        HStack(spacing: 1.5) {
            label
                .foregroundStyle((light ? Color.black : Color.white).opacity(0.85))
                .padding(.horizontal, 2)
                .frame(minWidth: Self.bodyWidth, maxHeight: .infinity)
                .background {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            shape.fill(ink.opacity(0.5))
                            Rectangle().fill(fillColor)
                                .frame(width: g.size.width * CGFloat(min(max(level, 0), 1)))
                        }
                    }
                }
                .clipShape(shape)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(ink.opacity(0.5))
                .frame(width: 2, height: 5)
        }
    }

    var fillColor: Color {
        if charging { return Theme.ok }
        return level >= 0.2 ? ink : color
    }

    var label: some View {
        // у молнии свои поля по бокам — к цифрам вплотную
        HStack(spacing: -0.5) {
            if charging { Image(systemName: "bolt.fill").font(.system(size: 8, weight: .black)) }
            Text("\(Int((level * 100).rounded()))")
                .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
        }
        .fixedSize()
    }
}

/// Лимит подписки Claude в строке меню: шкала расхода, за ней в две строки — какое окно («5 ч» или
/// «Нед») и сколько до сброса, дальше значок и проценты
struct MenuBarClaude: View {
    let widget: ClaudeWidget
    @ObservedObject var usage: ClaudeUsage
    @ObservedObject var settings: StatsSettings
    /// С подложкой или без; nil — как в настройках. Явно — для замера ширины до переключения
    var pill: Bool? = nil
    @Environment(\.colorScheme) private var scheme
    var onPill: Bool { pill ?? settings.menuPill }
    var ink: Color { menuBarInk(pill: onPill, scheme: scheme) }

    var body: some View {
        let w = usage.window(widget)
        HStack(spacing: 5) {
            if usage.needsAccount {
                // аккаунта нет — только приглашение подключить
                Text(L("Подключите Claude"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.75))
                sparkles
            } else {
                GaugeView(gauge: .bar(w?.spent ?? 0), color: claudeColor(w), ink: ink)
                    .frame(width: 24, height: 5)
                // нет данных — только тип окна, без «нет данных» и прочерков
                VStack(alignment: .leading, spacing: -1) {
                    Text(widget.menuBarLabel)
                    if let w { Text(resetShort(w)) }
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ink.opacity(0.55))
                sparkles
                if let w { percentText(w.spent, size: 12, warn: false, color: claudeNumberColor(w), ink: ink) }
            }
        }
        .menuBarPill(onPill, scheme: scheme)
        .animation(.easeOut(duration: 0.3), value: claudeColor(w))
    }

    var sparkles: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ink.opacity(0.75))
    }

    /// Сколько до сброса: «2ч 10м», «3д 4ч»
    func resetShort(_ w: UsageWindow) -> String {
        guard let reset = w.resetsAt else { return L("не начато") }
        if w.isReset { return L("сейчас") }
        return shortDuration(minutes: Int((reset.timeIntervalSinceNow / 60).rounded(.up)))
    }
}

/// Отдельный значок «Держать экран включенным» в строке меню — виден, пока режим включён:
/// оранжевый, а если выбран срок — с обратным отсчётом
struct MenuBarAwake: View {
    @ObservedObject var awake: KeepAwake
    @ObservedObject var settings: StatsSettings
    var pill: Bool? = nil
    @Environment(\.colorScheme) private var scheme
    var onPill: Bool { pill ?? settings.menuPill }

    var body: some View {
        // значок есть, только пока режим включён (StatusBarController)
        if awake.active { badge }
    }

    var badge: some View {
        HStack(spacing: 4) {
            // черта прорезает буквы насквозь — под ней видна подложка или строка меню
            SleepIcon(slashed: true, size: 11)
            // выбран срок — рядом обратный отсчёт; ширина под две цифры, чтобы соседи не прыгали
            if let until = awake.until {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ZStack(alignment: .leading) {
                        ForEach(["88" + L("ч"), "88" + L("м"), "88" + L("с")], id: \.self) { Text($0).hidden() }
                        Text(KeepAwake.shortRemaining(until: until, now: context.date))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
        }
        .foregroundStyle(Theme.awake)
        .menuBarPill(onPill, padding: 9, scheme: scheme)
    }
}

/// SwiftUI внутри кнопки строки меню, но клики проходят к самой кнопке — она открывает меню
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
