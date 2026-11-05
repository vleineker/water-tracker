import Foundation
import UserNotifications
import AppKit

@MainActor
@Observable
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    static let categoryId = "REMINDER"
    static let reminderRequestId = "gota.reminder"
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

    func postReminder() {
        let log = HydrationStore.shared.log
        let count = log.todayBottles
        let goal = log.settings.goalBottles
        let title = "Hora de beber água"
        let body = "Você bebeu \(count) de \(goal) garrafas hoje."

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryId

        let request = UNNotificationRequest(
            identifier: Self.reminderRequestId,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                Task { @MainActor in
                    NotificationManager.fallbackNotify(title: title, body: body)
                }
            }
        }
    }

    private static func fallbackNotify(title: String, body: String) {
        let script = "display notification \"\(body)\" with title \"\(title)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
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
        Task { @MainActor in
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
