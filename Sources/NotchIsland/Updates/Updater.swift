import AppKit
import Sparkle

/// Обновления с сервера (Sparkle). Список версий проверяется при запуске и раз в час;
/// новая версия скачивается в фоне — только разница, если она есть, — и тогда внизу острова
/// появляется зелёная кнопка «Обновить»: по нажатию приложение ставит версию и перезапускается.
/// Адрес списка и публичный ключ подписи — в Info.plist (SUFeedURL, SUPublicEDKey)
@MainActor
// Sparkle зовёт делегата окон на главном потоке, но протокол так не помечен
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    /// Найденная новая версия («1.2») — пока она есть, видна кнопка «Обновить»
    @Published private(set) var availableVersion: String?
    /// Версия уже скачана: кнопка ставит её сразу, без окон
    private var installNow: (() -> Void)?
    private var controller: SPUStandardUpdaterController!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
                                                  userDriverDelegate: self)
        // при запуске проверяем сразу (приложение живёт неделями — без этого первая проверка
        // ждала бы часового расписания), дальше Sparkle проверяет сам
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let updater = self?.controller.updater, updater.canCheckForUpdates else { return }
            updater.checkForUpdatesInBackground()
        }
    }

    /// Зелёная кнопка: скачанное — ставим и перезапускаемся; иначе — окно Sparkle с загрузкой
    func update() {
        if let installNow { installNow() } else { controller.checkForUpdates(nil) }
    }

    /// «Проверить обновления…» в меню — с окном Sparkle, даже если новых версий нет
    func checkForUpdates() { controller.checkForUpdates(nil) }

    // MARK: SPUUpdaterDelegate

    /// Новая версия скачалась в фоне и встанет при выходе. Наш значок живёт неделями —
    /// поэтому сразу показываем кнопку, а установку запускает она
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installNow = immediateInstallHandler
        availableVersion = item.displayVersionString
        return true
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Найденную по расписанию версию (когда скачать в фоне нельзя) показываем своей кнопкой,
    /// а не окном поверх работы
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                             andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !handleShowingUpdate { availableVersion = update.displayVersionString }
    }

    func standardUserDriverWillFinishUpdateSession() {
        // окно закрыли или отложили — кнопка остаётся, только если версия уже скачана
        if installNow == nil { availableVersion = nil }
    }
}
