import Foundation
import SystemConfiguration

/// Подробности для выпадающего меню значков статистики: жирная строка и под ней цифры помельче.
/// Читаются, когда меню открывают: то, что не нужно каждые 2 секунды (имя диска, подкачка, IP), —
/// прямо здесь
extension SystemStats {
    func menuHeader(_ s: Stat) -> (String, [String]) {
        switch s {
        case .cpu: return cpuHeader
        case .memory: return memoryHeader
        case .network: return networkHeader
        case .disk: return diskHeader
        case .battery: return batteryHeader
        }
    }

    // MARK: Процессор

    /// «Процессор — 29%», «Пользователь 21% · система 8% · простой 71%», «За минуту: в среднем 25%, пик 45%»,
    /// «Apple M4 · 10 ядер (4 производительных + 6 эффективных)»
    private var cpuHeader: (String, [String]) {
        var lines = [L("Пользователь %@ · система %@ · простой %@", pct(cpuUser), pct(cpuSystem), pct(max(0, 1 - cpu)))]
        if !cpuHistory.isEmpty {
            let avg = cpuHistory.reduce(0, +) / Double(cpuHistory.count)
            lines.append(L("За минуту: в среднем %@, пик %@", pct(avg), pct(cpuHistory.max() ?? 0)))
        }
        if let chip = Self.cpuDescription { lines.append(chip) }
        return (L("Процессор — %@", pct(cpu)), lines)
    }

    /// Модель и ядра не меняются — читаем один раз
    private static let cpuDescription: String? = {
        let brand = sysctlString("machdep.cpu.brand_string")
        guard let total = sysctlInt("hw.physicalcpu") else { return brand }
        var cores = countText(total, ru: ("ядро", "ядра", "ядер"), en: ("core", "cores"))
        if let p = sysctlInt("hw.perflevel0.physicalcpu"), let e = sysctlInt("hw.perflevel1.physicalcpu"), e > 0 {
            cores += " (" + L("%@ производительных + %@ эффективных", String(p), String(e)) + ")"
        }
        return [brand, cores].compactMap { $0 }.joined(separator: " · ")
    }()

    // MARK: Память

    /// «Память — занято 13,0 ГБ из 16,0 ГБ», «Приложения 8,1 ГБ · зарезервировано 2,3 ГБ · сжато 1,6 ГБ»,
    /// «Кэш файлов 2,4 ГБ · подкачка 2,0 ГБ», «Нагрузка на память: нормальная»
    private var memoryHeader: (String, [String]) {
        let gb = { formatBytes($0, binary: true) }
        var lines = [L("Приложения %@ · зарезервировано %@ · сжато %@", gb(memApp), gb(memWired), gb(memCompressed))]
        var cache = L("Кэш файлов %@", gb(memCached))
        if let swap = Self.swapUsed, swap > 0 { cache += " · " + L("подкачка %@", gb(swap)) }
        lines.append(cache)
        if let level = Self.sysctlInt("kern.memorystatus_vm_pressure_level") {
            let pressure = level >= 4 ? L("критическая") : level >= 2 ? L("повышенная") : L("нормальная")
            lines.append(L("Нагрузка на память: %@", pressure))
        }
        return (L("Память — занято %@ из %@", gb(memUsed), gb(memTotal)), lines)
    }

    /// Сколько занято в файле подкачки
    private static var swapUsed: Double? {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return nil }
        return Double(swap.xsu_used)
    }

    // MARK: Сеть

    /// «Сеть — ↓ 1,2 МБ/с · ↑ 40 КБ/с», «Пик за минуту: ↓ 5,0 МБ/с · ↑ 1,1 МБ/с», «Wi‑Fi · 192.168.1.23»
    private var networkHeader: (String, [String]) {
        var lines: [String] = []
        if !netInHistory.isEmpty {
            lines.append(L("Пик за минуту: ↓ %@ · ↑ %@",
                           formatSpeed(netInHistory.max() ?? 0), formatSpeed(netOutHistory.max() ?? 0)))
        }
        let links = Self.activeLinks
        lines += links.isEmpty ? [L("Не подключено")] : links
        return (L("Сеть — ↓ %@ · ↑ %@", formatSpeed(netIn), formatSpeed(netOut)), lines)
    }

    /// Подключения с адресом: «Wi‑Fi · 192.168.1.23», «Ethernet · 10.0.0.5» — имена как в настройках macOS
    private static var activeLinks: [String] {
        var addresses: [String: String] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }
        var p = ifaddr
        while let a = p {
            p = a.pointee.ifa_next
            let name = String(cString: a.pointee.ifa_name)
            guard name.hasPrefix("en"), a.pointee.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                  let sa = a.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), addresses[name] == nil else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            addresses[name] = String(cString: host)
        }
        var names: [String: String] = [:]
        for i in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            if let bsd = SCNetworkInterfaceGetBSDName(i) as String?,
               let display = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? {
                names[bsd] = display
            }
        }
        return addresses.keys.sorted().map { "\(names[$0] ?? $0) · \(addresses[$0]!)" }
    }

    // MARK: Диск

    /// «Macintosh HD — занято 86%», «Занято 425 ГБ из 494 ГБ», «Доступно 69,4 ГБ (из них 12 ГБ очищаемого)»
    private var diskHeader: (String, [String]) {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys)
        let total = Double(v?.volumeTotalCapacity ?? 0)
        let available = Double(v?.volumeAvailableCapacityForImportantUsage ?? 0)
        // macOS сама освобождает кэши и копии в iCloud, когда место нужно: оно входит в «доступно»
        let purgeable = max(0, available - Double(v?.volumeAvailableCapacity ?? 0))
        let name = v?.volumeLocalizedName ?? L("Диск")
        guard total > 0 else { return (name, []) }
        let used = total - available
        var free = L("Доступно %@", formatBytes(available))
        if purgeable >= 1e9 { free = L("Доступно %@ (из них %@ очищаемого)", formatBytes(available), formatBytes(purgeable)) }
        return (L("%@ — занято %@", name, pct(used / total)),
                [L("Занято %@ из %@", formatBytes(used), formatBytes(total)), free])
    }

    // MARK: Батарея

    /// «Батарея 33%», «Заряжается до 80% · 1 ч 11 мин», «Адаптер 35 Вт», «Здоровье 92% · 179 циклов»
    private var batteryHeader: (String, [String]) {
        var lines = [batteryState]
        let d = batteryDetails
        if let w = d.adapterWatts { lines.append(L("Адаптер %@ Вт", String(w))) }
        var health: [String] = []
        if let h = d.health { health.append(L("Здоровье %@", pct(h))) }
        if let c = d.cycles { health.append(countText(c, ru: ("цикл", "цикла", "циклов"), en: ("cycle", "cycles"))) }
        if !health.isEmpty { lines.append(health.joined(separator: " · ")) }
        return (L("Батарея %@", pct(battery?.level ?? 0)), lines)
    }

    // MARK: sysctl

    private static func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return Int(v)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
