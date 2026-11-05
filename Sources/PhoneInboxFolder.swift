import Foundation

/// Lê e limpa a pasta `Gota/inbox` do iCloud Drive, onde o Atalho do iPhone grava
/// uma garrafa por arquivo. As regras (nome do arquivo, dia, não contar duas vezes)
/// moram em `PhoneInbox`, no núcleo.
///
/// Toda falha (sem iCloud Drive, sem a pasta, permissão negada) vira lista vazia ou
/// arquivo que fica para a próxima leitura: nunca trava o app. Roda fora da thread
/// principal, porque o iCloud Drive pode demorar a responder.
enum PhoneInboxFolder {
    static let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    static let inbox = iCloudDrive.appendingPathComponent("Gota/inbox", isDirectory: true)

    /// Nomes dos arquivos da pasta. Se o iCloud Drive existe mas a pasta ainda não,
    /// cria `Gota/inbox` para ela aparecer no app Arquivos do iPhone.
    static func fileNames() -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: iCloudDrive.path) else { return [] }
        if !fm.fileExists(atPath: inbox.path) {
            do {
                try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
            } catch {
                NSLog("Gota: não deu para criar \(inbox.path): \(error.localizedDescription)")
            }
            return []
        }
        do {
            return try fm.contentsOfDirectory(atPath: inbox.path)
        } catch {
            NSLog("Gota: não deu para ler \(inbox.path): \(error.localizedDescription)")
            return []
        }
    }

    /// Apaga os arquivos já somados. O que falhar fica na pasta e é apagado numa
    /// leitura seguinte, sem somar de novo.
    static func delete(_ names: [String]) {
        let coordinator = NSFileCoordinator()
        for name in names {
            let file = inbox.appendingPathComponent(name)
            var coordinationError: NSError?
            coordinator.coordinate(writingItemAt: file, options: .forDeleting, error: &coordinationError) { url in
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    NSLog("Gota: não deu para apagar \(name): \(error.localizedDescription)")
                }
            }
            if let coordinationError {
                NSLog("Gota: não deu para apagar \(name): \(coordinationError.localizedDescription)")
            }
        }
    }
}
