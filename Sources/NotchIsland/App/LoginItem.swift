import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published var enabled = false
    @Published var needsApproval = false

    /// Автозапуск работает только у .app-бандла, установленного в /Applications
    var available: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    init() { refresh() }

    func refresh() {
        let st = SMAppService.mainApp.status
        enabled = (st == .enabled)
        needsApproval = (st == .requiresApproval)
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("NotchIsland: автозапуск: \(error.localizedDescription)")
        }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
