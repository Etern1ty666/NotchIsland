import Foundation
import AppKit
import IOKit
import IOKit.ps

/// Что с питанием — как в меню батареи macOS
enum PowerState: Equatable {
    /// От батареи
    case battery
    /// Заряжается — или зарядку только что подключили и macOS вот-вот её включит
    case charging
    /// От сети, стоит на пределе заряда (оптимизированная зарядка или ограничение в настройках)
    case held(Int)
    /// От сети, батарея полная
    case full
    /// От сети, но не заряжает: бережёт батарею, греется
    case notCharging
}

struct BatteryInfo: Equatable {
    var level: Double        // 0...1
    var state: PowerState
    /// До скольки процентов заряжается: предел (80%), пока до него не дошли, иначе 100
    var target: Int
    /// Сколько осталось: до разряда или до `target`. Есть всегда, пока разряжается или заряжается
    var minutes: Int?

    var charging: Bool { state == .charging }
    var onAC: Bool { state != .battery }

    /// «Заряжается до 80% · 1 ч 10 мин», «Зарядка на паузе на 80%», «От батареи · осталось 3 ч 10 мин»
    var statusText: String {
        let time = minutes.map { " · " + formatMinutes($0) } ?? ""
        switch state {
        case .battery: return L("От батареи") + (minutes.map { " · " + L("осталось %@", formatMinutes($0)) } ?? "")
        case .charging: return L("Заряжается до %@", "\(target)%") + time
        case .held(let p): return L("Зарядка на паузе на %@", "\(p)%")
        case .full: return L("Заряжена")
        case .notCharging: return L("От сети · не заряжается")
        }
    }
}

/// Подробности для меню значка: износ, циклы, адаптер — читаются, когда меню открывают
struct BatteryDetails {
    /// Сколько ёмкости осталось от новой батареи, 0...1
    var health: Double?
    var cycles: Int?
    var adapterWatts: Int?
}

/// Предел заряда из `pmset -g battlimit`: оптимизированная зарядка или ограничение в настройках
struct ChargeLimit: Equatable {
    var percent: Int
    var fraction: Double { Double(percent) / 100 }
}

/// Батарея как в системе: меняется в тот же миг, что и у macOS, и время есть всегда.
///
/// Откуда узнаём о переменах — без опроса:
/// - уведомление IOPS — подключили/отключили зарядку, сменился процент или время у macOS;
/// - сообщения драйвера батареи (AppleSmartBattery) — зарядка включилась или встала, сменился ток.
/// Таймер нужен только для отсчёта времени и сглаживания тока: раз в секунду сразу после
/// переключения (macOS включает зарядку через несколько секунд), дальше раз в 10 с.
///
/// Время. macOS после каждого переключения 2 минуты не считает его вовсе (PostChargeWaitSeconds), а с
/// пределом заряда считает до 100% вместе с паузой на пределе. Поэтому:
/// - от батареи — время macOS, а пока его нет — остаток ёмкости на сглаженный ток разряда;
/// - заряжается до 100% — время macOS (оно учитывает медленную дозарядку), пока нет — своя оценка;
/// - заряжается до предела — всегда своя оценка.
/// Ток берём, только когда драйвер обновил данные (раз в секунду при переменах, раз в минуту в покое) и
/// он уже установился: первые секунды после переключения он ещё разгоняется. Сглаженный ток помним
/// между запусками — сразу после переключения прикидка уже близка к правде
final class BatteryMonitor: ObservableObject {
    @Published private(set) var info: BatteryInfo?

    private let service: io_service_t
    private var powerSource: CFRunLoopSource?
    private var port: IONotificationPortRef?
    private var interest: io_object_t = 0
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private var limit: ChargeLimit?
    /// Когда сменилось питание: первые секунды зарядка ещё включается, первые 2 минуты macOS не знает времени
    private var switchedAt = Date.distantPast
    private var lastOnAC: Bool?
    private var lastState: PowerState?
    /// С какого момента нынешнее состояние: ток после перемены несколько секунд разгоняется
    private var stateSince = Date.distantPast
    /// Метка последних данных драйвера — ток учитываем один раз на каждое обновление
    private var lastUpdate: Int?
    private var lastUpdateAt = Date()
    private var current = Currents()
    private var lastLimitRead = Date.distantPast

    init() {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }   // Mac без батареи
        // предел — до первого показа, иначе на миг мелькнёт «до 100%» с временем macOS
        limit = Self.readLimit()
        lastLimitRead = Date()
        refresh()
        watch()
        schedule()
    }

    deinit {
        timer?.invalidate()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        if interest != 0 { IOObjectRelease(interest) }
        if let port { IONotificationPortDestroy(port) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if service != 0 { IOObjectRelease(service) }
    }

    // MARK: События

    private func watch() {
        let me = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue().refresh()
        }, me)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = source
        }
        if service != 0, let port = IONotificationPortCreate(kIOMainPortDefault) {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
            IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { ctx, _, _, _ in
                guard let ctx else { return }
                Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue().refresh()
            }, me, &interest)
            self.port = port
        }
        // после сна macOS пересчитывает время заново, а предел мог смениться
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.switchedAt = Date()
            self?.refresh()
            self?.refreshLimit()
            self?.schedule()
        }
    }

    /// Раз в секунду, пока питание только что сменилось, потом раз в 10 с
    private func schedule() {
        let fast = Date().timeIntervalSince(switchedAt) < 30
        let interval: TimeInterval = fast ? 1 : 10
        guard timer?.timeInterval != interval else { return }
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval / 10
        RunLoop.main.add(t, forMode: .common)   // не замирает, пока открыто меню
        timer = t
    }

    private func tick() {
        refresh()
        // предел может снять сама macOS (оптимизированная зарядка решила дозарядить) — раз в минуту
        if info?.onAC == true, Date().timeIntervalSince(lastLimitRead) > 60 { refreshLimit() }
        schedule()
    }

    // MARK: Состояние

    func refresh() {
        guard let r = read() else { info = nil; return }
        let now = Date()
        if let lastOnAC, lastOnAC != r.onAC {
            switchedAt = now
            refreshLimit()
            schedule()
        }
        lastOnAC = r.onAC

        let state = classify(r, now: now)
        if let lastState, lastState != state {
            stateSince = now
            if r.onAC { refreshLimit() }   // встала или пошла зарядка
        }
        lastState = state
        observeCurrent(r, state: state, now: now)

        var target = 100
        if state == .charging, let limit, r.level < limit.fraction - 0.005 { target = limit.percent }
        let b = BatteryInfo(level: r.level, state: state, target: target,
                            minutes: minutes(r, state: state, target: target))
        if b != info {
            info = b
            // ./build.sh dev — в терминале видно, что пришло от macOS и что показали
            if Self.debug {
                NSLog("%@", String(format: "battery ac=%d chg=%d ncr=%d amp=%.0f sys=%@ limit=%@ → %@",
                                   r.onAC ? 1 : 0, r.charging ? 1 : 0,
                                   r.notChargingReason, r.amperage, r.systemMinutes.map(String.init) ?? "-",
                                   limit.map { "\($0.percent)" } ?? "-", b.statusText))
            }
        }
    }

    private static let debug = CommandLine.arguments.contains("--dev")

    /// Сглаженный ток — по каждому новому замеру драйвера, когда он уже установился
    private func observeCurrent(_ r: Reading, state: PowerState, now: Date) {
        guard r.updateTime != lastUpdate else { return }
        let dt = min(max(now.timeIntervalSince(lastUpdateAt), 1), 120)
        lastUpdate = r.updateTime
        lastUpdateAt = now
        guard now.timeIntervalSince(stateSince) > 10 else { return }
        switch state {
        case .battery:
            // время macOS посчитано по среднему току за минуты — оно и есть лучший ток разряда
            if let m = r.systemMinutes, r.remaining > 0 {
                current.observe(drain: r.remaining / (Double(m) / 60), dt: dt)
            } else if r.amperage < -50 {
                current.observe(drain: -r.amperage, dt: dt)
            }
        case .charging where r.amperage > 50:
            current.observe(charge: r.amperage, dt: dt)
        default:
            break
        }
    }

    private func classify(_ r: Reading, now: Date) -> PowerState {
        guard r.onAC else { return .battery }
        if r.charging { return .charging }
        if let limit, r.level >= limit.fraction - 0.015 { return .held(limit.percent) }
        if r.fullyCharged || r.level >= 0.995 { return .full }
        // только подключили — macOS включает зарядку через несколько секунд, а пока называет причину
        // (128). Молния нужна сразу; если и через полминуты не заряжает — правда не заряжает
        if r.notChargingReason == 0 || now.timeIntervalSince(switchedAt) < 30 { return .charging }
        return .notCharging
    }

    private func minutes(_ r: Reading, state: PowerState, target: Int) -> Int? {
        switch state {
        case .battery:
            if let m = r.systemMinutes { return m }
            guard r.remaining > 0 else { return nil }
            return Self.round(r.remaining / current.drain(seed: 700) * 60)
        case .charging:
            // до 100% без предела — время macOS: оно знает, как медленно идёт дозарядка
            if target == 100, limit == nil || r.level >= limit!.fraction, let m = r.systemMinutes { return m }
            guard r.fullCapacity > 0 else { return nil }
            let seed = r.adapterWatts.map { Double($0) / 12 * 1000 * 0.6 } ?? 1500
            return Self.chargeMinutes(from: r.remaining, to: Double(target) / 100 * r.fullCapacity,
                                      full: r.fullCapacity, current: current.charge(seed: seed))
        case .held, .full, .notCharging:
            return nil
        }
    }

    /// До ~80% ток зарядки почти постоянный, выше батарея берёт всё меньше — грубо вдвое
    private static func chargeMinutes(from remaining: Double, to target: Double, full: Double, current: Double) -> Int {
        let knee = 0.8 * full
        let fast = max(0, min(target, knee) - remaining)
        let slow = max(0, target - max(remaining, knee))
        // выше колена текущий ток уже снижен — дальше падает не так сильно
        let slowCurrent = current * (remaining >= knee ? 0.75 : 0.5)
        return round((fast / current + slow / slowCurrent) * 60)
    }

    private static func round(_ m: Double) -> Int { max(1, Int(m.rounded())) }

    /// Износ, циклы и адаптер — для меню, по запросу
    func details() -> BatteryDetails {
        func prop(_ key: String) -> Any? {
            guard service != 0 else { return nil }
            return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let data = prop("BatteryData") as? [String: Any]
        let design = (data?["DesignCapacity"] as? NSNumber)?.doubleValue ?? (prop("DesignCapacity") as? NSNumber)?.doubleValue
        let nominal = (data?["NominalChargeCapacity"] as? NSNumber)?.doubleValue
            ?? (prop("NominalChargeCapacity") as? NSNumber)?.doubleValue
        var health: Double?
        if let design, let nominal, design > 0 { health = min(1, nominal / design) }
        let watts = info?.onAC == true ? ((prop("AdapterDetails") as? [String: Any])?["Watts"] as? NSNumber)?.intValue : nil
        return BatteryDetails(health: health, cycles: (prop("CycleCount") as? NSNumber)?.intValue, adapterWatts: watts)
    }

    // MARK: Предел заряда

    /// `pmset -g battlimit` — в фоне: отдельный процесс, хоть и быстрый
    private func refreshLimit() {
        lastLimitRead = Date()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let limit = Self.readLimit()
            DispatchQueue.main.async {
                guard let self, limit != self.limit else { return }
                self.limit = limit
                self.refresh()
            }
        }
    }

    /// Действующие пределы (Terminated = 0) — берём самый низкий
    private static func readLimit() -> ChargeLimit? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "battlimit"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        func value(_ key: String, in block: Substring) -> String? {
            guard let r = block.range(of: key + " = ") else { return nil }
            return block[r.upperBound...].prefix { $0 != ";" && $0 != "\n" }.trimmingCharacters(in: .whitespaces)
        }
        var best: ChargeLimit?
        for block in text.split(separator: "}") {
            guard value("Terminated", in: block) != "1",
                  let soc = value("chargeSocLimitSoc", in: block).flatMap(Int.init), soc > 0, soc < 100 else { continue }
            if best == nil || soc < best!.percent { best = ChargeLimit(percent: soc) }
        }
        return best
    }

    // MARK: Чтение

    /// Один замер: процент и состояние — как у macOS (IOPS), ток и ёмкость — с драйвера батареи
    private struct Reading {
        var level: Double
        var onAC: Bool
        var charging: Bool
        var fullyCharged: Bool
        /// Время macOS: до разряда или до полной; nil — «ещё считаю»
        var systemMinutes: Int?
        /// Средний ток, мА: + заряд, − разряд
        var amperage: Double
        /// Сколько в батарее и сколько влезает, мА·ч
        var remaining: Double
        var fullCapacity: Double
        var notChargingReason: Int
        var adapterWatts: Int?
        /// Когда драйвер последний раз обновил данные (с)
        var updateTime: Int
    }

    private func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = Double(d[kIOPSCurrentCapacityKey] as? Int ?? 0)
            let maxCap = Double(d[kIOPSMaxCapacityKey] as? Int ?? 100)
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = (onAC ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
            func prop(_ key: String) -> Any? {
                guard service != 0 else { return nil }
                return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
            }
            let data = prop("BatteryData") as? [String: Any]
            let charger = prop("ChargerData") as? [String: Any]
            let level = maxCap > 0 ? min(1, cur / maxCap) : 0
            let full = Double((data?["FullChargeCapacity"] as? NSNumber)?.intValue
                              ?? (prop("NominalChargeCapacity") as? NSNumber)?.intValue ?? 0)
            let remaining = (data?["RemainingCapacity"] as? NSNumber).map { Double($0.intValue) } ?? level * full
            return Reading(level: level,
                           onAC: onAC,
                           charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                           fullyCharged: (prop("FullyCharged") as? Bool) ?? false,
                           systemMinutes: minutes > 0 ? minutes : nil,
                           amperage: Double((prop("Amperage") as? NSNumber)?.int64Value ?? 0),
                           remaining: remaining,
                           fullCapacity: full,
                           notChargingReason: (charger?["NotChargingReason"] as? NSNumber)?.intValue ?? 0,
                           adapterWatts: ((prop("AdapterDetails") as? [String: Any])?["Watts"] as? NSNumber)?.intValue,
                           updateTime: (prop("UpdateTime") as? NSNumber)?.intValue ?? 0)
        }
        return nil
    }
}

/// Обычный ток зарядки и разряда этого Mac, сглаженный по времени: зарядка ровная (~1 мин), разряд
/// скачет с нагрузкой (~5 мин) — время не бегает от каждого всплеска. Помнится между запусками
private struct Currents {
    private var chargeMA = UserDefaults.standard.double(forKey: DefaultsKey.chargeCurrent)
    private var drainMA = UserDefaults.standard.double(forKey: DefaultsKey.drainCurrent)
    private var lastSaved = Date.distantPast

    func charge(seed: Double) -> Double { chargeMA > 0 ? chargeMA : seed }
    func drain(seed: Double) -> Double { drainMA > 0 ? drainMA : seed }

    mutating func observe(charge now: Double, dt: TimeInterval) {
        chargeMA = Self.smooth(chargeMA, now, dt: dt, tau: 60)
        save()
    }

    mutating func observe(drain now: Double, dt: TimeInterval) {
        drainMA = Self.smooth(drainMA, now, dt: dt, tau: 300)
        save()
    }

    private static func smooth(_ old: Double, _ new: Double, dt: TimeInterval, tau: Double) -> Double {
        guard old > 0 else { return new }
        return old + (new - old) * (1 - exp(-dt / tau))
    }

    private mutating func save() {
        guard Date().timeIntervalSince(lastSaved) > 60 else { return }
        lastSaved = Date()
        UserDefaults.standard.set(chargeMA, forKey: DefaultsKey.chargeCurrent)
        UserDefaults.standard.set(drainMA, forKey: DefaultsKey.drainCurrent)
    }
}
