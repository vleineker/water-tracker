import SwiftUI
import AppKit

@main
struct GotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Bindable private var store = HydrationStore.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// Só a gota, enchendo conforme o progresso do dia (cheia ao bater a meta).
    private var menuBarLabel: some View {
        Image(nsImage: MenuBarIcon.image(progress: store.log.progress))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Usado pelo uninstall.sh: desregistra o login item e sai, sem abrir painel/notificações.
        if CommandLine.arguments.contains("--unregister-login") {
            LoginItemManager.setEnabled(false)
            NSApp.terminate(nil)
            return
        }
        NotificationManager.shared.configure()
        HydrationStore.shared.onChange = { ReminderScheduler.shared.recompute() }
        ReminderScheduler.shared.start()
        LoginItemManager.registerDefaultIfFirstLaunch()
    }
}
