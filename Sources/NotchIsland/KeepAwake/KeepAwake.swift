import SwiftUI
import AppKit
import IOKit.pwr_mgt

final class KeepAwake: NSObject, ObservableObject {
    /// Сроки в меню; nil — пока не выключат вручную
    static let options: [(title: String, minutes: Int?)] = [
        ("30 минут", 30), ("1 час", 60), ("3 часа", 180), ("8 часов", 480), ("Всегда", nil),
    ]

    @Published private(set) var active = false
    /// Когда режим выключится сам; nil — держится, пока не выключат
    @Published private(set) var until: Date?
    /// Какой срок выбран (номер в options) — для галочки в меню и переключателя в настройках
    @Published private(set) var chosen: Int?
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

    /// Название режима — в меню и подсказках
    static let title = "Держать экран включенным"

    /// «Экран не гаснет ещё 1 ч 12 мин»; без срока — просто название режима
    var statusText: String {
        guard active, let until else { return Self.title }
        let m = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
        return "Экран не гаснет ещё \(formatMinutes(m))"
    }

    /// Сколько осталось — одной единицей для строки меню: «3ч», «25м», «40с».
    /// Округляем вверх: «25м» — осталось не больше 25 минут
    static func shortRemaining(until: Date, now: Date = Date()) -> String {
        let s = max(0, until.timeIntervalSince(now))
        if s > 3600 { return "\(Int((s / 3600).rounded(.up)))ч" }
        if s > 60 { return "\(Int((s / 60).rounded(.up)))м" }
        return "\(Int(s.rounded(.up)))с"
    }

    /// Меню сроков — одно и то же у кнопки на острове и в строке меню.
    /// header — с названием режима (у кнопки zzz); в строке меню название уже у пункта-родителя
    func makeMenu(header: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        fill(menu, header: header)
        return menu
    }

    /// Пункты меню сроков — в готовое меню. header — с названием режима и остатком времени
    /// (у кнопки zzz на острове); в строке меню — только сроки
    func fill(_ menu: NSMenu, header: Bool) {
        if header {
            let title = NSMenuItem(title: Self.title, action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
        }
        // сколько осталось — только когда выбран срок и только вместе с заголовком
        let timed = header && active && until != nil
        if timed {
            let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            status.isEnabled = false
            status.attributedTitle = NSAttributedString(string: status.title, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            menu.addItem(status)
        }
        if header || timed { menu.addItem(.separator()) }
        for (i, o) in Self.options.enumerated() {
            let item = NSMenuItem(title: o.title, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = active && chosen == i ? .on : .off
            menu.addItem(item)
        }
        if active {
            menu.addItem(.separator())
            let off = NSMenuItem(title: "Выключить", action: #selector(turnOff), keyEquivalent: "")
            off.target = self
            menu.addItem(off)
        }
    }

    /// Включить на срок из options (по номеру)
    func choose(_ index: Int) {
        enable(minutes: Self.options[index].minutes)
        if active { chosen = index }
    }

    @objc private func pick(_ sender: NSMenuItem) { choose(sender.tag) }

    @objc private func turnOff() { disable() }
}
