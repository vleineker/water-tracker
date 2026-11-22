import Foundation
import WidgetKit

/// Lado do app na conversa com o widget de desktop (ver `WidgetSnapshot`): grava o
/// retrato do dia a cada mudança e soma as garrafas que o widget deixou em `inbox/`.
@MainActor
enum WidgetBridge {
    private static var watcher: DispatchSourceFileSystemObject?

    /// Grava o retrato e pede ao macOS para redesenhar o widget.
    static func publish(_ snapshot: WidgetSnapshot) {
        guard snapshot != WidgetSnapshot.read() else { return }
        snapshot.write()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Soma o que já estiver na pasta e passa a vigiar a pasta por cliques novos.
    static func start() {
        let store = HydrationStore.shared
        publish(store.widgetSnapshot)
        drain()
        let descriptor = open(WidgetSnapshot.inbox.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { drain() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Uma garrafa por arquivo do dia de hoje. Apaga antes de somar: se não der para
    /// apagar, o arquivo fica para a próxima leitura em vez de contar duas vezes.
    /// Arquivo de outro dia é só apagado.
    private static func drain() {
        let fm = FileManager.default
        let store = HydrationStore.shared
        store.refreshDay()
        for name in (try? fm.contentsOfDirectory(atPath: WidgetSnapshot.inbox.path)) ?? [] {
            guard let day = WidgetSnapshot.tapDay(fromFileName: name),
                  (try? fm.removeItem(at: WidgetSnapshot.inbox.appendingPathComponent(name))) != nil
            else { continue }
            if day == store.todayKey { store.add(1) }
        }
    }
}
