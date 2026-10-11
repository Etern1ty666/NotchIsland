import SwiftUI

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var clip: ClipboardStore
    @ObservedObject var awake: KeepAwake
    /// Не @ObservedObject: замеры раз в 2 секунды перерисовывают только вкладку статистики
    let stats: SystemStats
    let statsSettings: StatsSettings
    let usage: ClaudeUsage
    let updater: Updater

    @Namespace private var tabNS

    var body: some View {
        let ex = state.expanded
        let peek = state.peeking && !ex
        // В покое плавные «ушки» даёт сам вырез. Подросший остров выходит за них —
        // рисуем свои, иначе по бокам торчат прямые углы
        let flare: CGFloat = ex ? Metrics.flareExpanded : (peek ? Metrics.flarePeek : 0)
        let bodyW: CGFloat = ex ? Metrics.expanded.width : state.notch.width + (peek ? Metrics.peek.width : 0)
        let h: CGFloat = ex ? state.expandedHeight : state.notch.height + (peek ? Metrics.peek.height : 0)
        let shape = IslandShape(top: flare, bottom: ex ? 24 : (peek ? 12 : 10))

        ZStack(alignment: .top) {
            // тень — только у фона, отдельным слоем: иначе любая подсветка внутри заставляла
            // пересчитывать размытую тень всего острова, и наведение подтормаживало
            shape.fill(Color.black)
                .shadow(color: Color.black.opacity(ex ? 0.45 : 0), radius: 14, y: 6)
            // содержимое при сворачивании гаснет быстрее формы — не сплющивается
            panelContent
                .frame(width: Metrics.expanded.width, height: state.expandedHeight, alignment: .top)
                .opacity(ex ? 1 : 0)
                .scaleEffect(ex ? 1 : 0.94, anchor: .top)
                .animation(ex ? Metrics.spring : .easeOut(duration: 0.15), value: ex)
                .allowsHitTesting(ex)
                .frame(width: bodyW + 2 * flare, height: h, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: bodyW + 2 * flare, height: h)
        // после установки и обновления: зелёное свечение вокруг выреза, пока остров не раскроют
        .background(alignment: .top) {
            if state.showHint && !ex {
                HintGlow(size: CGSize(width: bodyW + 2 * flare, height: h))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            // SwiftUI-анимация прерываема: при смене состояния она идёт от текущего значения
            .animation(ex ? Metrics.spring : Metrics.collapse, value: ex)
            // пока курсор ждёт на вырезе, остров плавно подрастает ровно за время задержки
            .animation(peek ? .easeOut(duration: Metrics.hoverDelay) : Metrics.collapse, value: peek)
    }

    var panelContent: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                if state.showSettings {
                    SettingsView(usage: usage, clip: clip, stats: stats, statsSettings: statsSettings,
                                 awake: awake, updater: updater)
                } else {
                    switch state.tab {
                    case .clipboard:
                        ClipboardTab(clip: clip, expanded: state.expanded)
                    case .stats:
                        StatsTab(stats: stats, settings: statsSettings, usage: usage,
                                 openSettings: { openSettings(true) })
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if state.updateBar {
                UpdateBar(updater: updater)
                    .frame(height: Metrics.updateBarHeight, alignment: .top)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Верхняя строка: вкладки слева от выреза, индикаторы справа, по центру — сам вырез

    func select(_ t: Tab) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            state.tab = t
            state.showSettings = false
        }
    }

    func openSettings(_ open: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.showSettings = open }
    }

    var topBar: some View {
        let side = max(0, (Metrics.expanded.width - state.notch.width) / 2)
        return HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { t in
                    TabButton(tab: t, selected: state.tab == t && !state.showSettings, ns: tabNS) { select(t) }
                }
            }
            .padding(.leading, 12)
            .frame(width: side, alignment: .leading)

            Color.clear.frame(width: state.notch.width)

            HStack(spacing: 6) {
                // «Держать экран включенным»: по клику — меню сроков прямо под кнопкой
                GeometryReader { g in
                    SleepButton(slashed: awake.active, help: awake.statusText) {
                        state.openAwakeMenu?(g.frame(in: .global))
                    }
                }
                .frame(width: 26, height: 26)
                CircleIconButton(systemName: "gearshape", help: "Настройки", active: state.showSettings) {
                    openSettings(!state.showSettings)
                }
            }
            .padding(.trailing, 12)
            .frame(width: side, alignment: .trailing)
        }
        .frame(height: state.topBarHeight)
    }
}

struct TabButton: View {
    let tab: Tab
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: 36, height: 26)
            .background {
                if selected {
                    Capsule().fill(Color.white.opacity(0.18)).matchedGeometryEffect(id: "tab", in: ns)
                } else if hover {
                    Capsule().fill(Color.white.opacity(0.08))
                }
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(hover ? 0.9 : 0.55))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tab.title)
        .accessibilityLabel(tab.title)
    }

    @ViewBuilder var icon: some View {
        switch tab {
        case .clipboard: Image(systemName: "list.clipboard").font(.system(size: 12, weight: .semibold))
        case .stats: BarsIcon().frame(width: 12, height: 11)
        }
    }
}

/// Значок статистики: три столбика — средний, высокий, низкий
struct BarsIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let gap = rect.width * 0.14
        let w = (rect.width - 2 * gap) / 3
        var p = Path()
        for (i, h) in [0.62, 1.0, 0.36].enumerated() {
            let height = rect.height * h
            let bar = CGRect(x: rect.minX + CGFloat(i) * (w + gap), y: rect.maxY - height, width: w, height: height)
            p.addRoundedRect(in: bar, cornerSize: CGSize(width: w / 2, height: w / 2), style: .continuous)
        }
        return p
    }
}

/// Пульсирующее зелёное свечение вокруг свёрнутого острова — подсказка «курсор сюда».
/// Форма выше острова и уходит за верх экрана: так бока светятся по всей высоте так же,
/// как низ, а отступ одинаковый слева, справа и снизу
struct HintGlow: View {
    let size: CGSize
    @State private var pulse = false

    var body: some View {
        let outset: CGFloat = 4, above: CGFloat = 24
        IslandShape(top: 0, bottom: 14)
            .fill(Theme.ok)
            .frame(width: size.width + 2 * outset, height: size.height + outset + above)
            .offset(y: -above)
            .blur(radius: pulse ? 9 : 5)
            .opacity(pulse ? 1 : 0.4)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}
