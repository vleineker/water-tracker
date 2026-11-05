import Foundation
import UserNotifications
import AppKit

@MainActor
@Observable
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    static let categoryId = "REMINDER"
    nonisolated static let testRequestId = "gota.test"
    private static let drinkActionId = "DRINK"
    private static let snoozeActionId = "SNOOZE"

    private(set) var authorized = false
    var authorizationDenied: Bool { !authorized }

    private override init() {}

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let drinkAction = UNNotificationAction(
            identifier: Self.drinkActionId,
            title: "Bebi uma garrafa",
            options: []
        )
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionId,
            title: "Lembrar em 15 min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [drinkAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshStatus()
                // Agendamentos feitos antes da permissão falham; refaz com ela.
                ReminderScheduler.shared.recompute()
            }
        }
    }

    /// Relê a autorização real do sistema — o resultado do `requestAuthorization`
    /// fica stale se o usuário muda a permissão depois (Ajustes do Sistema), então
    /// o painel precisa reconsultar toda vez que abre (ver `PanelView.onAppear`).
    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let isAuthorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            Task { @MainActor in
                self?.authorized = isAuthorized
            }
        }
    }

    /// Texto do lembrete, montado na hora de agendar.
    static func reminderContent(bottles: Int, goal: Int) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Hora de beber água"
        content.body = "Você bebeu \(bottles) de \(goal) garrafas hoje."
        content.sound = .default
        content.categoryIdentifier = categoryId
        return content
    }

    /// Botão "Testar lembrete": entrega na hora, fora do ritmo e sem contar como lembrete.
    func postReminder() {
        let log = HydrationStore.shared.log
        let request = UNNotificationRequest(
            identifier: Self.testRequestId,
            content: Self.reminderContent(bottles: log.todayBottles, goal: log.settings.goalBottles),
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Gota: falha no lembrete de teste: \(error.localizedDescription)") }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionId = response.actionIdentifier
        let deliveredAt = response.notification.date
        let isTest = response.notification.request.identifier == NotificationManager.testRequestId
        Task { @MainActor in
            if !isTest {
                ReminderScheduler.shared.noteDelivered(at: deliveredAt)
            }
            switch actionId {
            case NotificationManager.drinkActionId:
                HydrationStore.shared.add(1)
            case NotificationManager.snoozeActionId:
                ReminderScheduler.shared.snooze(minutes: 15)
            default:
                break
            }
            completionHandler()
        }
    }
}
