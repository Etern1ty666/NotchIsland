import SwiftUI
import AppKit

@MainActor
final class IslandController: NSObject {
    let state = IslandState()
    let clip = ClipboardStore()
    let awake = KeepAwake()
    let panel: IslandPanel
    let hitPanel: HitPanel
    private(set) var screen: NSScreen
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    /// Открыто выпадающее меню — курсор может уйти за край острова, сворачивать нельзя
    private var menuOpen = false
    /// Остров открыли из меню в строке меню: курсор ещё там — не сворачиваем, пока он не дойдёт до острова
    private var holdOpen = false
    /// Проверка курсора уже запланирована — события мыши идут пачками, хватит одной на пачку
    private var movePending = false

    init(stats: SystemStats, statsSettings: StatsSettings, usage: ClaudeUsage, updater: Updater) {
        screen = Self.pickScreen() ?? NSScreen.screens[0]
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        hitPanel = HitPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        super.init()
        state.notch = Self.notchSize(on: screen)

        for p in [panel, hitPanel] as [NSPanel] {
            p.isFloatingPanel = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.isMovable = false
        }
        panel.acceptsMouseMovedEvents = true

        let host = NSHostingView(rootView: IslandView(state: state, clip: clip, awake: awake,
                                                     stats: stats, statsSettings: statsSettings, usage: usage,
                                                     updater: updater))
        host.sizingOptions = []
        if #available(macOS 13.3, *) { host.safeAreaRegions = [] }
        panel.contentView = host

        let hit = HitView()
        hit.onClick = { [weak self] in self?.expand() }
        hit.onHover = { [weak self] in self?.mouseMoved() }
        hitPanel.contentView = hit

        // Окно всегда размера раскрытого острова (плюс запас под тень), меняется только форма внутри (SwiftUI)
        layout()
        panel.ignoresMouseEvents = true
        hitPanel.ignoresMouseEvents = false   // явно: иначе прозрачное окно пропускает клики насквозь
        hitPanel.orderFrontRegardless()
        panel.orderFrontRegardless()

        state.openAwakeMenu = { [weak self] r in self?.showAwakeMenu(below: r) }

        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.scheduleMouseMoved()
        }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.scheduleMouseMoved()
            return e
        }
        // Подключили монитор, сменили разрешение, закрыли крышку — пересчитываем положение
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }
    }

    // MARK: Геометрия

    /// Экран со встроенным вырезом, иначе — основной (со строкой меню)
    static func pickScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    static func notchSize(on s: NSScreen) -> CGSize {
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        }
        // Mac без выреза: рисуем «вырез» сами, высотой со строку меню
        let menuBar = s.frame.maxY - s.visibleFrame.maxY
        return CGSize(width: 180, height: menuBar > 0 ? menuBar : 24)
    }

    func layout() {
        guard let s = Self.pickScreen() else { return }
        screen = s
        state.notch = Self.notchSize(on: s)
        // окно — под самую высокую вкладку; форма острова внутри меняется сама
        let w = Metrics.expanded.width + 2 * Metrics.flareExpanded
        let h = Metrics.maxHeight
        let island = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        panel.setFrame(NSRect(x: island.minX - Metrics.margin.width,
                              y: island.minY - Metrics.margin.height,
                              width: island.width + 2 * Metrics.margin.width,
                              height: island.height + Metrics.margin.height), display: true)
        hitPanel.setFrame(collapsedHit, display: false)
    }

    var collapsedRect: NSRect {
        let w = state.notch.width, h = state.notch.height
        return NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }
    var expandedRect: NSRect {
        let w = Metrics.expanded.width + 2 * Metrics.flareExpanded, h = state.expandedHeight
        return NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }
    var collapsedHit: NSRect { collapsedRect.insetBy(dx: -2, dy: -2) }
    var expandedHit: NSRect { expandedRect.insetBy(dx: -2, dy: -2) }

    // MARK: Наведение

    func mouseMoved() {
        let p = NSEvent.mouseLocation
        if state.expanded {
            if expandedHit.contains(p) { holdOpen = false }
            if expandedHit.contains(p) || menuOpen || holdOpen {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.collapseWork = nil
                    if !self.menuOpen && !self.expandedHit.contains(NSEvent.mouseLocation) { self.collapse() }
                }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.leaveDelay, execute: work)
            }
        } else if collapsedHit.contains(p) {
            // «намерение»: раскрываем, только если курсор задержался на вырезе —
            // так остров не срабатывает, когда мышь просто проезжает к иконкам в строке меню
            guard expandWork == nil else { return }
            state.peeking = true
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.expandWork = nil
                if !self.state.expanded && self.collapsedHit.contains(NSEvent.mouseLocation) {
                    self.expand()
                } else {
                    self.state.peeking = false
                }
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.hoverDelay, execute: work)
        } else {
            cancelExpand()
        }
    }

    private func scheduleMouseMoved() {
        guard !movePending else { return }
        movePending = true
        DispatchQueue.main.async { [weak self] in
            self?.movePending = false
            self?.mouseMoved()
        }
    }

    /// Меню сроков «Держать экран включенным» под кнопкой на острове
    func showAwakeMenu(below r: CGRect) {
        // .global у SwiftUI — от левого верхнего угла окна острова; переводим в координаты экрана.
        // Верх меню держим ниже строки меню, иначе macOS обрезает его и показывает стрелку прокрутки
        let y = min(panel.frame.maxY - r.maxY - 6, screen.visibleFrame.maxY - 8)
        let p = NSPoint(x: panel.frame.minX + r.minX, y: y)
        menuOpen = true
        // открываем после того, как SwiftUI закончит обработку клика: popUp ждёт, пока меню
        // закроется, и прямо внутри действия кнопки держал бы SwiftUI посреди обновления —
        // подсветка пунктов меню от этого отставала
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.awake.makeMenu(header: true).popUp(positioning: nil, at: p, in: nil)
            self.menuOpen = false
            self.mouseMoved()
        }
    }

    func cancelExpand() {
        expandWork?.cancel()
        expandWork = nil
        if state.peeking { state.peeking = false }
    }

    /// «Настройки…» в меню значка: раскрываем остров сразу на настройках. Ждём курсор до 10 секунд
    func showSettings() {
        state.showSettings = true
        expand()
        holdOpen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.holdOpen else { return }
            self.holdOpen = false
            self.mouseMoved()
        }
    }

    func expand() {
        cancelExpand()
        collapseWork?.cancel()
        collapseWork = nil
        guard !state.expanded else { return }
        // Свежий скриншот (последние 15 секунд) — сразу показываем буфер, он там первый
        if clip.scanScreenshots() { state.tab = .clipboard }
        panel.ignoresMouseEvents = false
        hitPanel.ignoresMouseEvents = true
        state.expanded = true
    }

    func collapse() {
        collapseWork?.cancel()
        collapseWork = nil
        guard state.expanded else { return }
        state.expanded = false
        panel.ignoresMouseEvents = true
        hitPanel.ignoresMouseEvents = false
        // при следующем раскрытии — снова вкладки; меняем, когда содержимое уже погасло
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.state.expanded else { return }
            self.state.showSettings = false
        }
    }
}
