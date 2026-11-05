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

    @ViewBuilder
    private var menuBarLabel: some View {
        let log = store.log
        if store.settings.showCountInBar {
            HStack(spacing: 4) {
                dropImage(log)
                Text("\(log.todayBottles)/\(log.settings.goalBottles)")
            }
        } else {
            dropImage(log)
        }
    }

    @ViewBuilder
    private func dropImage(_ log: HydrationLog) -> some View {
        if let nsImage = Self.menubarImage(named: dropAssetName(log)) {
            Image(nsImage: nsImage)
        } else {
            Image(systemName: log.metGoalToday ? "drop.fill" : "drop")
        }
    }

    private func dropAssetName(_ log: HydrationLog) -> String {
        if log.metGoalToday {
            return "drop-full"
        }
        if log.todayBottles > 0 {
            return "drop-half"
        }
        return "drop-empty"
    }

    private static var menubarImageCache: [String: NSImage] = [:]

    private static func menubarImage(named name: String) -> NSImage? {
        if let cached = menubarImageCache[name] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "menubar"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        menubarImageCache[name] = image
        return image
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
