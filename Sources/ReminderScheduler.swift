import Foundation
import Observation

@MainActor
@Observable
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private(set) var nextReminderAt: Date?
    private var timer: Timer?

    private init() {}

    func start() {
        recompute()
        guard timer == nil else { return }
        let heartbeat = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        heartbeat.tolerance = 5
        RunLoop.main.add(heartbeat, forMode: .common)
        timer = heartbeat
    }

    func recompute() {
        let settings = HydrationStore.shared.settings
        nextReminderAt = Self.next(after: Date(), settings: settings, intervalOverrideSeconds: debugIntervalOverride)
    }

    func snooze(minutes: Int) {
        nextReminderAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    private var debugIntervalOverride: Int? {
        let value = UserDefaults.standard.integer(forKey: "gota.debugIntervalSeconds")
        return value > 0 ? value : nil
    }

    private func tick() {
        HydrationStore.shared.refreshDay()
        guard let next = nextReminderAt else {
            recompute()
            return
        }
        guard Date() >= next else { return }

        let log = HydrationStore.shared.log
        let hour = Calendar.current.component(.hour, from: Date())
        let withinWindow = hour >= log.settings.startHour && hour < log.settings.endHour
        if withinWindow && !log.metGoalToday {
            NotificationManager.shared.postReminder()
        }
        recompute()
    }

    /// Função pura: próximo horário de lembrete a partir de `date`, dada a janela ativa
    /// (startHour–endHour) e o intervalo configurado (ou override de debug, em segundos).
    /// - antes do início da janela -> início da janela hoje
    /// - depois do fim da janela -> início da janela amanhã
    /// - dentro da janela -> date + intervalo, ou início de amanhã se isso passar do fim
    static func next(after date: Date, settings: Settings, intervalOverrideSeconds: Int? = nil) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let windowStart = calendar.date(byAdding: .hour, value: settings.startHour, to: startOfDay) ?? date
        let windowEnd = calendar.date(byAdding: .hour, value: settings.endHour, to: startOfDay) ?? date
        let intervalSeconds = intervalOverrideSeconds ?? (settings.intervalMin * 60)

        if date < windowStart {
            return windowStart
        }
        if date >= windowEnd {
            return calendar.date(byAdding: .day, value: 1, to: windowStart) ?? date
        }
        let candidate = date.addingTimeInterval(TimeInterval(intervalSeconds))
        if candidate > windowEnd {
            return calendar.date(byAdding: .day, value: 1, to: windowStart) ?? candidate
        }
        return candidate
    }
}
