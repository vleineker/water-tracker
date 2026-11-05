import Foundation
import Observation
import AppKit
import SwiftUI

/// Só guarda e observa: lê/grava o estado em `gota.state.v2` (migrando a `v1` na
/// primeira abertura, ver `StateMigration`) e acompanha a troca de dia. Toda regra (meta batida, progresso, streak, validação) mora em `HydrationLog`.
@MainActor
@Observable
final class HydrationStore {
    static let shared = HydrationStore()

    /// Chamado depois de cada mudança feita pelo usuário (garrafa somada/removida ou
    /// ajuste alterado). O `AppDelegate` liga isto ao agendador de lembretes.
    @ObservationIgnored var onChange: (() -> Void)?

    private(set) var settings: Settings
    /// ml por dia. As garrafas exibidas saem daqui ÷ `bottleML` atual (no núcleo).
    private(set) var mlByDay: [String: Int]
    private(set) var metGoal: [String: Bool]
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
        self.today = Self.calendar.startOfDay(for: Date())

        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDay() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDay() }
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

    private var todayKey: String {
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
        mlByDay[todayKey] = HydrationLog.ml(mlByDay[todayKey] ?? 0, adding: delta, bottleML: settings.bottleML)
        recordTodayGoal()
        trimHistory()
        persist()
        onChange?()
    }

    func updateSettings(_ newSettings: Settings) {
        settings = HydrationLog.validated(newSettings, from: settings)
        refreshDay()
        // Meta nova vale para hoje na hora, sem esperar a próxima garrafa.
        recordTodayGoal()
        persist()
        onChange?()
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
        Self.write(PersistedState(settings: settings, mlByDay: mlByDay, metGoal: metGoal))
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
