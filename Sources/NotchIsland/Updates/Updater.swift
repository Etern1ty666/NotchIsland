import AppKit
import Sparkle

/// Обновления с сервера (Sparkle) со своим интерфейсом: никаких окон — состояние и прогресс
/// показывают зелёная кнопка внизу острова и строка «Версия» в настройках.
/// Список версий проверяется при запуске и раз в час; новая версия обычно скачивается в фоне
/// (только разница, если она есть), и кнопка ставит её сразу.
/// Адрес списка и публичный ключ подписи — в Info.plist (SUFeedURL, SUPublicEDKey)
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUUserDriver {
    enum Phase: Equatable {
        case idle
        case checking
        /// Проверили по кнопке — новее нет
        case upToDate
        /// Есть новая версия, ещё не скачана
        case available(String)
        /// 0…1; nil — размер пока неизвестен
        case downloading(Double?)
        case extracting(Double)
        /// Скачана и распакована — по кнопке встанет и перезапустит приложение
        case ready(String)
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    /// Показывать полосу с кнопкой внизу острова: есть что ставить или уже ставим
    var showsBar: Bool {
        switch phase {
        case .available, .downloading, .extracting, .ready, .installing: return true
        case .failed: return foundVersion != nil
        default: return false
        }
    }

    private var updater: SPUUpdater!
    private var foundVersion: String?
    /// Скачано в фоне: поставить сейчас, не дожидаясь выхода
    private var installNow: (() -> Void)?
    /// Ответ Sparkle на «нашлась версия» / «готово к установке» — даём, когда нажали «Обновить»
    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    override init() {
        super.init()
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            try updater.start()
        } catch {
            NSLog("NotchIsland: обновления: \(error.localizedDescription)")
            return
        }
        // при запуске проверяем сразу (приложение живёт неделями — без этого первая проверка
        // ждала бы часового расписания), дальше Sparkle проверяет сам
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let updater = self?.updater, updater.canCheckForUpdates else { return }
            updater.checkForUpdatesInBackground()
        }
    }

    // MARK: Кнопки

    /// «Проверить обновления» в настройках
    func checkForUpdates() {
        guard installNow == nil, foundReply == nil, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    /// «Обновить»: скачанное — ставим и перезапускаемся; найденное — скачиваем и ставим;
    /// после ошибки — проверяем заново
    func update() {
        if let installNow {
            self.installNow = nil
            phase = .installing
            installNow()
        } else if let reply = foundReply {
            foundReply = nil
            reply(.install)
        } else {
            foundVersion = nil
            phase = .idle
            checkForUpdates()
        }
    }

    // MARK: SPUUpdaterDelegate

    /// Новая версия скачалась в фоне и встанет при выходе. Наш значок живёт неделями —
    /// поэтому сразу показываем кнопку, а установку запускает она
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installNow = immediateInstallHandler
        foundVersion = item.displayVersionString
        phase = .ready(item.displayVersionString)
        return true
    }

    // MARK: SPUUserDriver — всё, что Sparkle показал бы окнами

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = appcastItem.displayVersionString
        foundVersion = version
        foundReply = reply
        switch state.stage {
        case .notDownloaded: phase = .available(version)
        case .downloaded: phase = .ready(version)
        case .installing: phase = .installing
        @unknown default: phase = .available(version)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        phase = .upToDate
        // «Последняя версия» — пару секунд, потом снова кнопка «Проверить»
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.phase == .upToDate { self?.phase = .idle }
        }
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        foundReply = nil
        phase = .failed(error.localizedDescription)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        phase = .downloading(nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        phase = .downloading(expectedLength > 0 ? min(1, Double(receivedLength) / Double(expectedLength)) : nil)
    }

    func showDownloadDidStartExtractingUpdate() {
        phase = .extracting(0)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        phase = .extracting(progress)
    }

    /// Сюда попадаем только после нажатия «Обновить» — ставим сразу
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        phase = .installing
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        phase = .idle
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        // сессия закончилась; скачанное в фоне остаётся ждать кнопку
        foundReply = nil
        switch phase {
        case .ready where installNow != nil, .failed, .upToDate: break
        default:
            foundVersion = nil
            phase = .idle
        }
    }
}
