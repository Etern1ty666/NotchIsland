import SwiftUI
import AppKit
import IOKit.pwr_mgt

final class KeepAwake: NSObject, ObservableObject {
    /// Сроки в меню; nil — пока не выключат вручную
    static let options: [(title: String, minutes: Int?)] = [
        ("На 30 минут", 30), ("На 1 час", 60), ("На 3 часа", 180), ("На 8 часов", 480), ("Пока не выключу", nil),
    ]

    @Published private(set) var active = false
    /// Когда режим выключится сам; nil — держится, пока не выключат
    @Published private(set) var until: Date?
    /// Какой срок выбран — для галочки в меню
    private var chosen: Int?
    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    func enable(minutes: Int?) {
        if !active {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NotchIsland: экран не гаснет" as CFString,
                &assertionID)
            guard result == kIOReturnSuccess else { return }
        }
        // повторный выбор срока просто перезапускает отсчёт
        timer?.invalidate()
        timer = nil
        if let minutes {
            let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
            let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.disable() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            until = end
        } else {
            until = nil
        }
        active = true
    }

    func disable() {
        timer?.invalidate()
        timer = nil
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        chosen = nil
        until = nil
        active = false
    }

    /// Что именно делает режим: держит экран включённым, а с ним и Mac — без сна по бездействию
    static let title = "Не гасить экран и не усыплять Mac"

    /// «Экран не гаснет и Mac не уснёт ещё 1 ч 12 мин»
    var statusText: String {
        guard active else { return Self.title }
        guard let until else { return "Экран не гаснет и Mac не уснёт, пока не выключишь" }
        let m = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
        return "Экран не гаснет и Mac не уснёт ещё \(formatMinutes(m))"
    }

    /// Меню сроков — одно и то же у кнопки на острове и в строке меню
    func makeMenu(header: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if active || header {
            let info = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            // режим не спасает от сна при закрытой крышке — предупреждаем честно
            let note = NSMenuItem(title: "Mac не уснёт от бездействия. Закрытая крышка всё равно усыпит его",
                                  action: nil, keyEquivalent: "")
            note.isEnabled = false
            note.attributedTitle = NSAttributedString(string: note.title, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            menu.addItem(note)
            menu.addItem(.separator())
        }
        for (i, o) in Self.options.enumerated() {
            let item = NSMenuItem(title: o.title, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = active && chosen == i ? .on : .off
            menu.addItem(item)
        }
        if active {
            menu.addItem(.separator())
            let off = NSMenuItem(title: "Выключить — Mac снова может засыпать", action: #selector(turnOff), keyEquivalent: "")
            off.target = self
            menu.addItem(off)
        }
        return menu
    }

    @objc private func pick(_ sender: NSMenuItem) {
        enable(minutes: Self.options[sender.tag].minutes)
        if active { chosen = sender.tag }
    }

    @objc private func turnOff() { disable() }
}
