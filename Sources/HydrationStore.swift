import Foundation
import Observation
import AppKit
import SwiftUI

/// Só guarda e observa: lê/grava o estado em `gota.state.v2` (migrando a `v1` na
/// primeira abertura, ver `StateMigration`), acompanha a troca de dia e traz as
/// garrafas do Atalho do iPhone (`importPhoneInbox`). Toda regra (meta batida,
/// progresso, streak, validação, arquivos do iPhone, fila do Garmin) mora no núcleo.
///
/// Com o Garmin ligado, cada mudança vira um item de `garminQueue` e o total de hoje
/// passa a ser o do Garmin mais a fila (`applyGarminToday`). Desligado, a fila não muda.
@MainActor
@Observable
final class HydrationStore {
    static let shared = HydrationStore()

    /// Chamado depois de cada mudança feita pelo usuário (garrafa somada/removida ou
    /// ajuste alterado). O `AppDelegate` liga isto ao agendador de lembretes.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Chamado quando há algo para levar ao Garmin (garrafa nova, interruptor ligado).
    /// O `AppDelegate` liga isto ao `GarminSyncer`.
    @ObservationIgnored var onGarminWork: ((GarminTrigger) -> Void)?

    private(set) var settings: Settings
    /// ml por dia. As garrafas exibidas saem daqui ÷ `bottleML` atual (no núcleo).
    private(set) var mlByDay: [String: Int]
    private(set) var metGoal: [String: Bool]
    /// Arquivos do Atalho do iPhone já somados (ver `PhoneInbox`).
    @ObservationIgnored private var importedFiles: [String]
    /// Garrafas ainda não enviadas ao Garmin, na ordem do registro.
    private(set) var garminQueue: [GarminPending]
    @ObservationIgnored private var garminLastRead: GarminRead?
    /// Evita duas leituras da pasta do iPhone ao mesmo tempo.
    @ObservationIgnored private var importingPhoneInbox = false
    @ObservationIgnored private var phoneInboxTimer: Timer?
    /// Início do dia corrente. Guardado (e não lido do relógio a cada acesso) para a
    /// troca de dia disparar a atualização da interface.
    private(set) var today: Date

    /// Calendário fixo gregoriano para as chaves `yyyy-MM-dd` não mudarem com o
    /// calendário escolhido no sistema.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    private init() {
        let loaded = HydrationStore.load()
        self.settings = loaded.settings
        self.mlByDay = loaded.mlByDay
        self.metGoal = loaded.metGoal
        self.importedFiles = loaded.importedFiles
        self.garminQueue = loaded.garminQueue
        self.garminLastRead = loaded.garminLastRead
        self.today = Self.calendar.startOfDay(for: Date())

        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDay() }
        }
        // O aviso de acordar vem do centro do NSWorkspace, não do `default`.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDay()
                self?.importPhoneInbox()
            }
        }
    }

    /// Retrato do estado atual para o núcleo de regras.
    var log: HydrationLog {
        HydrationLog(
            settings: settings,
            mlByDay: mlByDay,
            metGoalByDay: metGoal,
            now: today,
            calendar: Self.calendar
        )
    }

    var todayKey: String {
        HydrationLog.dayKey(for: today, calendar: Self.calendar)
    }

    func refreshDay() {
        let start = Self.calendar.startOfDay(for: Date())
        if start != today {
            today = start
        }
    }

    func add(_ delta: Int) {
        refreshDay()
        let before = mlByDay[todayKey] ?? 0
        let after = HydrationLog.ml(before, adding: delta, bottleML: settings.bottleML)
        mlByDay[todayKey] = after
        var queued = false
        if settings.garminEnabled,
           let entry = GarminSync.pending(ml: after - before, at: Date(), calendar: Self.calendar, id: UUID().uuidString) {
            garminQueue.append(entry)
            queued = true
        }
        recordTodayGoal()
        trimHistory()
        persist()
        onChange?()
        if queued { onGarminWork?(.bottle) }
    }

    func updateSettings(_ newSettings: Settings) {
        let wasGarminEnabled = settings.garminEnabled
        settings = HydrationLog.validated(newSettings, from: settings)
        refreshDay()
        let switchedOn = settings.garminEnabled && !wasGarminEnabled
        if switchedOn, let entry = GarminSync.catchUp(
            todayML: mlByDay[todayKey] ?? 0, todayKey: todayKey, lastRead: garminLastRead,
            queue: garminQueue, at: Date(), calendar: Self.calendar, id: UUID().uuidString
        ) {
            garminQueue.append(entry)
        }
        // Meta nova vale para hoje na hora, sem esperar a próxima garrafa.
        recordTodayGoal()
        persist()
        onChange?()
        if switchedOn { onGarminWork?(.switchedOn) }
    }

    // MARK: - Garmin

    /// Resposta do `add` de um item da fila: ele só sai com `ok:true`.
    func garminSent(_ id: String, reply: GarminReply) {
        let updated = GarminSync.queue(garminQueue, afterSending: id, reply: reply)
        guard updated != garminQueue else { return }
        garminQueue = updated
        persist()
    }

    /// Total de hoje lido do Garmin. Substitui o ml de hoje pelo do Garmin mais o que
    /// de hoje ainda está na fila, para meta, streak, gota e lembrete contarem também
    /// o que veio do relógio. A meta continua sendo a do Gota.
    func applyGarminToday(_ garminML: Int, dayKey: String) {
        refreshDay()
        guard dayKey == todayKey else { return }
        let read = GarminRead(dayKey: dayKey, ml: garminML)
        let total = GarminSync.todayTotal(garminML: garminML, queue: garminQueue, todayKey: todayKey)
        guard total != (mlByDay[todayKey] ?? 0) || read != garminLastRead else { return }
        garminLastRead = read
        mlByDay[todayKey] = total
        recordTodayGoal()
        trimHistory()
        persist()
        onChange?()
    }

    // MARK: - Atalho do iPhone

    /// Lê a pasta do iPhone agora e a cada 15 min. As outras leituras acontecem ao
    /// acordar o Mac (observador no `init`) e ao abrir o painel (`PanelView`).
    func startPhoneInbox() {
        if phoneInboxTimer == nil {
            let timer = Timer(timeInterval: 15 * 60, repeats: true) { _ in
                Task { @MainActor in HydrationStore.shared.importPhoneInbox() }
            }
            timer.tolerance = 60
            RunLoop.main.add(timer, forMode: .common)
            phoneInboxTimer = timer
        }
        importPhoneInbox()
    }

    /// Soma as garrafas gravadas pelo Atalho do iPhone e apaga os arquivos somados.
    /// Grava o estado antes de apagar: se o app cair no meio, o arquivo que sobrar
    /// já está em `importedFiles` e não soma de novo.
    func importPhoneInbox() {
        guard !importingPhoneInbox else { return }
        importingPhoneInbox = true
        Task {
            let names = await Task.detached { PhoneInboxFolder.fileNames() }.value
            refreshDay()
            let outcome = PhoneInbox.importing(
                names,
                into: PersistedState(settings: settings, mlByDay: mlByDay, metGoal: metGoal, importedFiles: importedFiles, garminQueue: garminQueue)
            )
            if outcome.addedBottles > 0 {
                mlByDay = outcome.state.mlByDay
                metGoal = outcome.state.metGoal
                importedFiles = outcome.state.importedFiles
                if settings.garminEnabled {
                    garminQueue += outcome.addedStamps.map {
                        GarminSync.pending(from: $0, ml: settings.bottleML, id: UUID().uuidString)
                    }
                }
                recordTodayGoal()
                trimHistory()
                persist()
                NSLog("Gota: \(outcome.addedBottles) garrafa(s) do iPhone somada(s)")
                onChange?()
                if settings.garminEnabled { onGarminWork?(.bottle) }
            }
            if !outcome.filesToDelete.isEmpty {
                let files = outcome.filesToDelete
                await Task.detached { PhoneInboxFolder.delete(files) }.value
            }
            importingPhoneInbox = false
        }
    }

    /// Binding genérico para um campo de Settings — usado pelos Steppers/Toggles do painel.
    func binding<T>(_ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = self.settings
                updated[keyPath: keyPath] = newValue
                self.updateSettings(updated)
            }
        )
    }

    /// Grava o resultado de hoje para que, virado o dia, ele fique congelado no streak.
    private func recordTodayGoal() {
        guard mlByDay[todayKey] != nil else { return }
        metGoal[todayKey] = log.metGoalToday
    }

    private func trimHistory() {
        guard mlByDay.count > 30 else { return }
        let sortedKeys = mlByDay.keys.sorted()
        let excess = sortedKeys.count - 30
        for key in sortedKeys.prefix(excess) {
            mlByDay.removeValue(forKey: key)
            metGoal.removeValue(forKey: key)
        }
    }

    private func persist() {
        Self.write(PersistedState(
            settings: settings, mlByDay: mlByDay, metGoal: metGoal,
            importedFiles: importedFiles, garminQueue: garminQueue, garminLastRead: garminLastRead
        ))
    }

    private static func write(_ state: PersistedState) {
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(encoded, forKey: StateMigration.v2Key)
    }

    /// Lê a `v2`; se só houver `v1`, converte e já grava a `v2`, para a conversão
    /// rodar uma vez só. A `v1` fica gravada como cópia do dado antigo.
    private static func load() -> PersistedState {
        let defaults = UserDefaults.standard
        let (state, source) = StateMigration.resolve(
            v2: defaults.data(forKey: StateMigration.v2Key),
            v1: defaults.data(forKey: StateMigration.v1Key)
        )
        if source == .migratedFromV1 {
            write(state)
        }
        return state
    }
}
