import Foundation

/// LaunchAgent de reserva que abre o Gota ao iniciar sessão quando
/// `SMAppService.mainApp.register()` falha.
///
/// É puro: diz onde fica o arquivo, o que vai dentro e quando ele deve sair. Gravar e
/// apagar o arquivo fica em `LoginItemManager`.
enum LaunchAgentFallback {
    static let label = "com.vleineker.gota"

    /// `~/Library/LaunchAgents/com.vleineker.gota.plist` dentro da pasta pessoal `home`.
    static func plistPath(home: String) -> String {
        (home as NSString).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Conteúdo do plist: abre o app em `appPath` ao iniciar sessão.
    static func contents(appPath: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
        ]
    }

    /// Arquivo a apagar quando o "Abrir ao iniciar sessão" muda para `enabled`.
    ///
    /// Desligar tira o plist de reserva, se ele existir, senão ele segue abrindo o app
    /// sozinho mesmo com o login item desligado. Ligar nunca apaga nada.
    static func pathToRemove(enabled: Bool, home: String, fileExists: (String) -> Bool) -> String? {
        guard !enabled else { return nil }
        let path = plistPath(home: home)
        return fileExists(path) ? path : nil
    }
}
