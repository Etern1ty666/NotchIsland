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

        // корень на языке системы: сменили язык — остров строится заново на новом
        let state = self.state, clip = self.clip, awake = self.awake
        let host = TrackingHostingView(rootView: LocalizedRoot {
            IslandView(state: state, clip: clip, awake: awake,
                       stats: stats, statsSettings: statsSettings, usage: usage, updater: updater)
        })
        host.sizingOptions = []
        if #available(macOS 13.3, *) { host.safeAreaRegions = [] }
        panel.contentView = host

        let hit = HitView()
        hit.onClick = { [weak self] in self?.expand() }
        hit.onHover = { [weak self] in self?.mouseMoved() }
        hitPanel.contentView = hit

        // Окно всегда размера раскрытого острова (плюс запас под тень), меняется только форма внутри (SwiftUI)
        panel.ignoresMouseEvents = true
        hitPanel.ignoresMouseEvents = false   // явно: иначе прозрачное окно пропускает клики насквозь
        layout()
        hitPanel.orderFrontRegardless()
        panel.orderFrontRegardless()

        state.openAwakeMenu = { [weak self] r in self?.showAwakeMenu(below: r) }

        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.forwardMouseMove()
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

    /// Встроенный экран с вырезом включён (крышка открыта), но ни один экран сейчас выреза не показывает
    static func notchUnused() -> Bool {
        guard !NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 }) else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsAsleep($0) == 0 && hasNotch($0) }
    }

    /// Матрица с вырезом выше 16:10 — над привычной картинкой полоса под вырез
    /// (3024×1964, 3456×2234, 2560×1664…), у MacBook без выреза ровно 16:10.
    /// Смотрим самый крупный режим: он не зависит от выбранного разрешения
    static func hasNotch(_ id: CGDirectDisplayID) -> Bool {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] ?? []
        guard let m = modes.max(by: { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }),
              m.pixelWidth > 0 else { return false }
        return Double(m.pixelHeight) / Double(m.pixelWidth) > 0.635
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

        // спрятанному острову окно-ловушка не нужно: оно перехватывало бы клики по строке меню
        let hidden = Self.notchUnused()
        if hidden != state.hidden {
            cancelExpand()
            state.hidden = hidden
        }
        if hidden { hitPanel.orderOut(nil) } else { hitPanel.orderFrontRegardless() }
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
    /// Где курсор будит свёрнутый остров. Спрятанный — только тонкая полоса у самого края
    /// (курсор, упёртый вверх, туда попадает, а строке меню она не мешает). Когда остров уже выглянул — весь его силуэт.
    /// Упёртый в край курсор стоит ровно на maxY, а contains верхнюю границу не включает — полоса заходит за край
    var hoverHit: NSRect {
        guard state.hidden && !state.peeking else { return collapsedHit }
        return NSRect(x: collapsedRect.minX, y: screen.frame.maxY - 3, width: collapsedRect.width, height: 5)
    }

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
        } else if hoverHit.contains(p) {
            // «намерение»: раскрываем, только если курсор задержался на вырезе —
            // так остров не срабатывает, когда мышь просто проезжает к иконкам в строке меню
            guard expandWork == nil else { return }
            state.peeking = true
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.expandWork = nil
                if !self.state.expanded && self.hoverHit.contains(NSEvent.mouseLocation) {
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

    /// macOS отдаёт движения мыши то острову, то активному приложению под ним — вразнобой, хотя остров
    /// сверху: окну, которое никогда не становится активным, они достаются ненадёжно. Тогда SwiftUI не узнаёт,
    /// что курсор переехал, и подсветка залипает на прежней плитке, а под курсором не появляется.
    /// Движение, доставшееся другому приложению, над раскрытым островом передаём острову сами.
    /// С меню «не засыпать» то же самое: подсветка пункта под курсором залипала — его отслеживание
    /// берёт события из очереди приложения, туда и кладём
    private func forwardMouseMove() {
        let p = NSEvent.mouseLocation
        if menuOpen {
            if let e = NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                                          context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                NSApp.postEvent(e, atStart: false)
            }
            return
        }
        guard state.expanded, let host = panel.contentView, panel.frame.contains(p),
              let e = NSEvent.mouseEvent(with: .mouseMoved, location: panel.convertPoint(fromScreen: p),
                                         modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: panel.windowNumber, context: nil,
                                         eventNumber: 0, clickCount: 0, pressure: 0)
        else { return }
        host.mouseMoved(with: e)
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

    /// «Настройки…» в меню значка: раскрываем остров сразу на настройках (прокрутив к anchor).
    /// Ждём курсор до 10 секунд
    func showSettings(at anchor: String? = nil) {
        state.settingsAnchor = anchor
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
        Localizer.shared.refresh()
        // остров всегда открывается на буфере; заодно подхватываем свежие скриншоты
        state.tab = .clipboard
        clip.scanScreenshots()
        panel.ignoresMouseEvents = false
        hitPanel.ignoresMouseEvents = true
        state.expanded = true
        if state.showHint {
            state.showHint = false
            UserDefaults.standard.set(Updater.currentVersion, forKey: DefaultsKey.islandHintVersion)
        }
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
