import AppKit

/// «Мониторинг системы» на нужной вкладке. Вкладку он помнит в своей настройке SelectedTab и читает
/// её только при запуске — если он уже открыт, закрываем его (при выходе он записывает свою вкладку)
/// и открываем заново на нашей
enum ActivityMonitor {
    enum Tab: Int {
        case cpu = 0, memory, energy, disk, network
    }

    static let bundleID = "com.apple.ActivityMonitor"

    static func tab(for stat: Stat) -> Tab {
        switch stat {
        case .cpu: return .cpu
        case .memory: return .memory
        case .network: return .network
        case .disk: return .disk
        case .battery: return .energy
        }
    }

    @MainActor static func open(_ tab: Tab) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return launch(tab) }
        running.forEach { $0.terminate() }
        waitAndLaunch(tab, attempts: 30)
    }

    /// Ждём до 3 секунд, пока закроется, — потом открываем в любом случае
    @MainActor private static func waitAndLaunch(_ tab: Tab, attempts: Int) {
        let stillRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isTerminated }
        guard stillRunning, attempts > 0 else { return launch(tab) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { waitAndLaunch(tab, attempts: attempts - 1) }
    }

    @MainActor private static func launch(_ tab: Tab) {
        CFPreferencesSetAppValue("SelectedTab" as CFString, tab.rawValue as CFNumber, bundleID as CFString)
        CFPreferencesAppSynchronize(bundleID as CFString)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
