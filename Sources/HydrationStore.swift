import Foundation
import Observation
import AppKit
import SwiftUI

private struct Persisted: Codable {
    var settings: Settings = Settings()
    var history: [String: Int] = [:]
    var metGoal: [String: Bool] = [:]

    init() {}

    init(settings: Settings, history: [String: Int], metGoal: [String: Bool]) {
        self.settings = settings
        self.history = history
        self.metGoal = metGoal
    }

    private enum CodingKeys: String, CodingKey { case settings, history, metGoal }

    // Decode manual: dado persistido da v1 não tem `metGoal` — sem isto, o decode
    // falha inteiro e reseta settings/history também.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        history = try container.decodeIfPresent([String: Int].self, forKey: .history) ?? [:]
        metGoal = try container.decodeIfPresent([String: Bool].self, forKey: .metGoal) ?? [:]
    }
}

/// Só guarda e observa: lê/grava o estado em `gota.state.v1` e acompanha a troca
/// de dia. Toda regra (meta batida, progresso, streak, validação) mora em `HydrationLog`.
@MainActor
@Observable
final class HydrationStore {
    static let shared = HydrationStore()

    private static let defaultsKey = "gota.state.v1"

    /// Chamado depois de cada mudança feita pelo usuário (garrafa somada/removida ou
    /// ajuste alterado). O `AppDelegate` liga isto ao agendador de lembretes.
    @ObservationIgnored var onChange: (() -> Void)?

    private(set) var settings: Settings
    /// Garrafas por dia (formato v1). O núcleo recebe isso convertido para ml.
    private(set) var history: [String: Int]
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
        self.history = loaded.history
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
            mlByDay: history.mapValues { $0 * settings.bottleML },
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
        history[todayKey] = max(0, (history[todayKey] ?? 0) + delta)
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
        guard history[todayKey] != nil else { return }
        metGoal[todayKey] = log.metGoalToday
    }

    private func trimHistory() {
        guard history.count > 30 else { return }
        let sortedKeys = history.keys.sorted()
        let excess = sortedKeys.count - 30
        for key in sortedKeys.prefix(excess) {
            history.removeValue(forKey: key)
            metGoal.removeValue(forKey: key)
        }
    }

    private func persist() {
        let data = Persisted(settings: settings, history: history, metGoal: metGoal)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: HydrationStore.defaultsKey)
    }

    private static func load() -> Persisted {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            return Persisted()
        }
        return decoded
    }
}
