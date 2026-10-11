import SwiftUI
import AppKit
import IOKit
import IOKit.ps

final class SystemStats: ObservableObject {
    /// Сколько замеров храним для графиков (раз в 2 с -> последняя минута)
    static let historyLength = 30

    @Published private(set) var cpu: Double = 0          // 0...1, всё вместе
    @Published private(set) var cpuUser: Double = 0
    @Published private(set) var cpuSystem: Double = 0
    @Published private(set) var cpuHistory: [Double] = []

    let memTotal = Double(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var memUsed: Double = 0
    @Published private(set) var memHistory: [Double] = []

    @Published private(set) var netIn: Double = 0        // байт/с
    @Published private(set) var netOut: Double = 0
    @Published private(set) var netHistory: [Double] = []

    @Published private(set) var diskFree: Double = 0
    @Published private(set) var diskTotal: Double = 0

    @Published private(set) var battery: BatteryInfo?

    var memFraction: Double { memTotal > 0 ? memUsed / memTotal : 0 }
    var diskUsedFraction: Double { diskTotal > 0 ? 1 - diskFree / diskTotal : 0 }
    /// Скорость сети для графика: делим на пик за минуту (но не меньше 100 КБ/с, чтобы шум не выглядел нагрузкой)
    var netGraph: [Double] {
        let peak = max(netHistory.max() ?? 0, 100_000)
        return netHistory.map { $0 / peak }
    }
    /// У Mac без батареи (iMac, Mac mini) карточки и значка батареи нет
    var available: [Stat] { Stat.allCases.filter { $0 != .battery || battery != nil } }

    private let host = mach_host_self()
    private var prevTicks: [UInt32]?
    private var prevNet: [String: (UInt32, UInt32)] = [:]
    private var prevNetTime: Date?
    private var tick = 0
    private var timer: Timer?

    init() {
        prevTicks = cpuTicks()
        sampleNetwork()
        sampleMemory()
        sampleDisk()
        battery = Self.readBattery(previous: nil)
        // первый замер чуть раньше, чтобы цифры появились сразу после запуска
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sample() }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)   // не замирает, пока открыто меню
        timer = t
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        tick += 1
        if tick % 5 == 0 { battery = Self.readBattery(previous: battery) }   // раз в 10 с
        if tick % 15 == 0 { sampleDisk() }                   // раз в 30 с
    }

    private static func push(_ v: Double, to a: inout [Double]) {
        a.append(v)
        if a.count > historyLength { a.removeFirst(a.count - historyLength) }
    }

    // MARK: Процессор

    /// Счётчики тиков всех ядер с момента загрузки: user, system, idle, nice
    private func cpuTicks() -> [UInt32]? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return [t.0, t.1, t.2, t.3]
    }

    private func sampleCPU() {
        guard let now = cpuTicks() else { return }
        defer { prevTicks = now }
        guard let prev = prevTicks else { return }
        let d = zip(now, prev).map { Double($0 &- $1) }   // &- : счётчики могут переполниться
        let total = d.reduce(0, +)
        guard total > 0 else { return }
        cpuUser = (d[0] + d[3]) / total
        cpuSystem = d[1] / total
        cpu = cpuUser + cpuSystem
        Self.push(cpu, to: &cpuHistory)
    }

    // MARK: Память

    private func sampleMemory() {
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        // как «Использовано» в «Мониторинге системы»: память приложений + неперемещаемая + сжатая
        let page = Double(vm_kernel_page_size)
        let app = max(0, Double(vm.internal_page_count) - Double(vm.purgeable_count))
        memUsed = (app + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
        Self.push(memFraction, to: &memHistory)
    }

    // MARK: Сеть

    private func sampleNetwork() {
        var now: [String: (UInt32, UInt32)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        var p = ifaddr
        while let a = p {
            p = a.pointee.ifa_next
            let name = String(cString: a.pointee.ifa_name)
            // только физические интерфейсы (Wi‑Fi, Ethernet): через VPN (utun) идёт тот же трафик,
            // он посчитался бы дважды
            guard name.hasPrefix("en"), a.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  a.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = a.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            now[name] = (data.pointee.ifi_ibytes, data.pointee.ifi_obytes)
        }
        freeifaddrs(ifaddr)
        let t = Date()
        if let pt = prevNetTime, t.timeIntervalSince(pt) > 0 {
            var din = 0.0, dout = 0.0
            for (n, v) in now {
                guard let pv = prevNet[n] else { continue }
                din += Double(v.0 &- pv.0)   // 32-битные счётчики переполняются — &- это учитывает
                dout += Double(v.1 &- pv.1)
            }
            let dt = t.timeIntervalSince(pt)
            netIn = din / dt
            netOut = dout / dt
            Self.push(netIn + netOut, to: &netHistory)
        }
        prevNet = now
        prevNetTime = t
    }

    // MARK: Диск и батарея

    private func sampleDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        diskTotal = Double(v.volumeTotalCapacity ?? 0)
        diskFree = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    /// Сколько осталось, macOS иногда не знает («ещё считаю» — после пробуждения, отключения зарядки,
    /// а то и посреди работы). Тогда держим прошлое значение, пока не сменилось питание, а если
    /// его нет — спрашиваем контроллер батареи напрямую (оттуда же время берёт pmset)
    static func readBattery(previous: BatteryInfo?) -> BatteryInfo? {
        guard var b = readPowerSource() else { return nil }
        if b.minutesLeft == nil {
            if let previous, previous.charging == b.charging, previous.onAC == b.onAC {
                b.minutesLeft = previous.minutesLeft
            } else if b.charging || !b.onAC {
                b.minutesLeft = smartBatteryMinutes(charging: b.charging)
            }
        }
        return b
    }

    /// Среднее время до разряда (или до полной) у контроллера батареи; 65535 — «неизвестно»
    private static func smartBatteryMinutes(charging: Bool) -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let key = (charging ? "AvgTimeToFull" : "AvgTimeToEmpty") as CFString
        guard let v = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int, v > 0, v < 65535 else { return nil }
        return v
    }

    private static func readPowerSource() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = Double(d[kIOPSCurrentCapacityKey] as? Int ?? 0)
            let maxCap = Double(d[kIOPSMaxCapacityKey] as? Int ?? 100)
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
            return BatteryInfo(level: maxCap > 0 ? min(1, cur / maxCap) : 0,
                               charging: charging,
                               onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                               minutesLeft: minutes > 0 ? minutes : nil)
        }
        return nil
    }

    // MARK: Для интерфейса

    func icon(_ s: Stat) -> String {
        switch s {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .battery:
            guard let b = battery else { return "battery.100" }
            if b.charging { return "battery.100.bolt" }
            switch b.level {
            case 0.88...: return "battery.100"
            case 0.63...: return "battery.75"
            case 0.38...: return "battery.50"
            case 0.13...: return "battery.25"
            default: return "battery.0"
            }
        }
    }

    func color(_ s: Stat) -> Color {
        switch s {
        case .cpu: return loadColor(cpu)
        // macOS держит память занятой под кэш — 80% для неё норма, краснеет только ближе к пределу
        case .memory: return loadColor(memFraction, calm: 0.75, busy: 0.9)
        case .network: return Color(red: 0.42, green: 0.72, blue: 1)
        case .disk: return loadColor(diskUsedFraction, calm: 0.8, busy: 0.92)
        case .battery:
            let l = battery?.level ?? 1
            if battery?.charging == true || l >= 0.2 { return Theme.ok }
            return l >= 0.1 ? Theme.warning : Theme.critical
        }
    }

    func gauge(_ s: Stat) -> Gauge {
        switch s {
        case .cpu: return .graph(cpuHistory)
        case .memory: return .graph(memHistory)
        case .network: return .graph(netGraph)
        case .disk: return .bar(diskUsedFraction)
        case .battery: return .bar(battery?.level ?? 0)
        }
    }

    /// Одна строка для подсказки у значка в строке меню
    func summary(_ s: Stat) -> String {
        switch s {
        case .cpu: return L("Процессор %@: пользователь %@, система %@", pct(cpu), pct(cpuUser), pct(cpuSystem))
        case .memory: return L("Память: занято %@ из %@", formatBytes(memUsed, binary: true), formatBytes(memTotal, binary: true))
        case .network: return L("Сеть: ↓ %@, ↑ %@", formatSpeed(netIn), formatSpeed(netOut))
        case .disk: return L("Диск: свободно %@ из %@", formatBytes(diskFree), formatBytes(diskTotal))
        case .battery: return L("Батарея %@ · %@", pct(battery?.level ?? 0), batteryState)
        }
    }

    /// «Заряжается · до полной 40 мин», «От батареи · осталось 3 ч 10 мин»
    var batteryState: String {
        guard let b = battery else { return "" }
        if b.charging { return L("Заряжается") + (b.minutesLeft.map { " · " + L("до полной %@", formatMinutes($0)) } ?? "") }
        if b.onAC { return L("От сети") }
        return L("От батареи") + (b.minutesLeft.map { " · " + L("осталось %@", formatMinutes($0)) } ?? "")
    }
}
