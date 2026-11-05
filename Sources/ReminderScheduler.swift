import Foundation
import AppKit
import UserNotifications

/// Entrega ao sistema os lembretes calculados pelo núcleo (`HydrationLog.upcomingReminders`).
///
/// Não há timer no app: cada lembrete vira um `UNNotificationRequest` com gatilho de
/// horário, então o macOS entrega mesmo com o app parado em App Nap. A lista é refeita
/// a cada garrafa somada ou removida, ajuste, virada do dia, volta do sono, mudança de
/// relógio ou fuso, e "Lembrar em 15 min".
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    /// Quantos lembretes ficam agendados de uma vez (o macOS aceita até 64 por app).
    private static let maxPending = 24
    private static let idPrefix = "gota.reminder."

    private enum Key {
        static let lastReminderAt = "gota.reminder.lastDeliveredAt"
        static let lastDrinkAt = "gota.reminder.lastDrinkAt"
        static let snoozedUntil = "gota.reminder.snoozedUntil"
        static let scheduled = "gota.reminder.scheduled"
        static let debugGap = "gota.debugIntervalSeconds"
    }

    private let defaults = UserDefaults.standard
    /// Último total visto (dia, tamanho da garrafa, ml) para perceber uma garrafa somada.
    private var lastSeen: (day: String, bottleML: Int, ml: Int)?
    private var observing = false

    private init() {}

    func start() {
        if !observing {
            observing = true
            let names: [(NotificationCenter, Notification.Name)] = [
                (NotificationCenter.default, .NSCalendarDayChanged),
                (NotificationCenter.default, .NSSystemClockDidChange),
                (NotificationCenter.default, .NSSystemTimeZoneDidChange),
                (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            ]
            for (center, name) in names {
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    Task { @MainActor in ReminderScheduler.shared.recompute() }
                }
            }
        }
        recompute()
    }

    /// Recalcula e substitui todos os lembretes pendentes no sistema.
    func recompute() {
        let store = HydrationStore.shared
        store.refreshDay()
        let now = Date()
        let log = store.log
        noteDrinkIfAny(log, now: now)
        noteDeliveredScheduled(before: now)

        // Nada toca antes de 1 s: é o menor gatilho do sistema, e o horário guardado
        // precisa ser o real para um recálculo logo em seguida não contar como entregue.
        let times = log.upcomingReminders(
            after: now,
            lastReminderAt: date(Key.lastReminderAt),
            lastDrinkAt: date(Key.lastDrinkAt),
            snoozedUntil: date(Key.snoozedUntil),
            minimumGap: minimumGap(log.settings),
            limit: Self.maxPending
        ).map { max($0, now.addingTimeInterval(1)) }

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for (index, fireDate) in times.enumerated() {
            let request = UNNotificationRequest(
                identifier: Self.idPrefix + String(index),
                content: NotificationManager.reminderContent(bottles: bottles(in: log, on: fireDate), goal: log.settings.goalBottles),
                trigger: Self.trigger(for: fireDate, now: now)
            )
            center.add(request) { error in
                if let error { NSLog("Gota: falha ao agendar lembrete: \(error.localizedDescription)") }
            }
        }
        defaults.set(times.map(\.timeIntervalSince1970), forKey: Key.scheduled)
        NSLog("Gota: \(times.count) lembrete(s) agendado(s); próximo: \(times.first.map { "\($0)" } ?? "nenhum")")
    }

    /// "Lembrar em 15 min": vale no lugar do espaço mínimo, só se o dia seguir atrasado.
    func snooze(minutes: Int) {
        let now = Date()
        noteDelivered(at: now)
        defaults.set(now.addingTimeInterval(TimeInterval(minutes * 60)), forKey: Key.snoozedUntil)
        recompute()
    }

    /// Registra um lembrete que o Vitor viu (tocou no aviso ou em uma ação).
    func noteDelivered(at deliveredAt: Date) {
        if deliveredAt > (date(Key.lastReminderAt) ?? .distantPast) {
            defaults.set(deliveredAt, forKey: Key.lastReminderAt)
        }
    }

    // MARK: - Privado

    /// O app não roda na hora da entrega, então o último lembrete agendado cujo
    /// horário já passou conta como entregue. Guardado em disco, sobrevive a reinício.
    private func noteDeliveredScheduled(before now: Date) {
        let scheduled = (defaults.array(forKey: Key.scheduled) as? [Double] ?? [])
            .map(Date.init(timeIntervalSince1970:))
        if let fired = scheduled.filter({ $0 <= now }).max() {
            noteDelivered(at: fired)
        }
    }

    private func noteDrinkIfAny(_ log: HydrationLog, now: Date) {
        let current = (day: log.todayKey, bottleML: log.settings.bottleML, ml: log.todayML)
        if let lastSeen, lastSeen.day == current.day, lastSeen.bottleML == current.bottleML,
           current.ml > lastSeen.ml {
            defaults.set(now, forKey: Key.lastDrinkAt)
        }
        lastSeen = current
    }

    private func minimumGap(_ settings: Settings) -> TimeInterval {
        let debug = defaults.integer(forKey: Key.debugGap)
        return TimeInterval(debug > 0 ? debug : settings.intervalMin * 60)
    }

    private func bottles(in log: HydrationLog, on date: Date) -> Int {
        guard log.settings.bottleML > 0 else { return 0 }
        let ml = log.mlByDay[HydrationLog.dayKey(for: date, calendar: log.calendar)] ?? 0
        return ml / log.settings.bottleML
    }

    private func date(_ key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    /// Horário de parede para datas futuras; para "agora" (atrasado e sem espaço a
    /// esperar), um intervalo curto, porque um gatilho de calendário no passado não toca.
    private static func trigger(for fireDate: Date, now: Date) -> UNNotificationTrigger {
        let interval = fireDate.timeIntervalSince(now)
        if interval < 60 {
            return UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
