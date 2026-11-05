import Foundation
import ServiceManagement
import AppKit
import Observation

/// Namespace sobre SMAppService.mainApp — login item do Gota.
enum LoginItemManager {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// Liga/desliga o login item. Retorna uma mensagem de erro para a UI, ou nil se ok.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        if let fallback = LaunchAgentFallback.pathToRemove(
            enabled: enabled, home: NSHomeDirectory(),
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        ) {
            do {
                try FileManager.default.removeItem(atPath: fallback)
            } catch {
                return "Não foi possível remover \(fallback): \(error.localizedDescription)"
            }
        }
        do {
            if enabled {
                if status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if status == .enabled || status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
            return nil
        } catch {
            if enabled {
                return registerFallbackLaunchAgent()
                    ? nil
                    : "Não foi possível registrar o login item: \(error.localizedDescription)"
            }
            return "Não foi possível remover o login item: \(error.localizedDescription)"
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Liga o login item uma única vez, no primeiro launch, conforme decisão de produto.
    /// Guardado por `gota.didRegisterLoginItem` para não forçar religamento se o usuário desligar depois.
    static func registerDefaultIfFirstLaunch() {
        let key = "gota.didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        _ = setEnabled(true)
    }

    /// Fallback apenas se SMAppService.register() falhar.
    private static func registerFallbackLaunchAgent() -> Bool {
        let plistPath = LaunchAgentFallback.plistPath(home: NSHomeDirectory())
        let plist = LaunchAgentFallback.contents(appPath: Bundle.main.bundlePath)
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        ) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                atPath: (plistPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try data.write(to: URL(fileURLWithPath: plistPath))
            return true
        } catch {
            return false
        }
    }
}

/// Espelho observável do status de login item para a UI — evita `@State`
/// (macro indisponível em toolchain sem Xcode; ver pitfalls do plano).
@MainActor
@Observable
final class LoginItemUIState {
    static let shared = LoginItemUIState()

    var enabled: Bool
    var needsApproval: Bool
    var errorMessage: String?

    private init() {
        enabled = LoginItemManager.isEnabled
        needsApproval = LoginItemManager.requiresApproval
    }

    func setEnabled(_ value: Bool) {
        errorMessage = LoginItemManager.setEnabled(value)
        enabled = LoginItemManager.isEnabled
        needsApproval = LoginItemManager.requiresApproval
    }
}
