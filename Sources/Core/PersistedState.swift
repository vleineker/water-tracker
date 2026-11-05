import Foundation

/// Estado salvo em `gota.state.v2`: quanto foi bebido em cada dia, em ml.
///
/// Guardar ml (e não garrafas) deixa o passado fixo: mudar o tamanho da garrafa
/// nos Ajustes não reescreve os litros de dias anteriores. As garrafas exibidas
/// são sempre recalculadas a partir do ml e do tamanho de garrafa atual.
struct PersistedState: Codable, Equatable {
    var settings: Settings = Settings()
    /// ml por dia, pela chave `yyyy-MM-dd`.
    var mlByDay: [String: Int] = [:]
    /// Resultado congelado de cada dia (meta batida ou não), usado pelo streak.
    var metGoal: [String: Bool] = [:]
    /// Arquivos do Atalho do iPhone já somados (ver `PhoneInbox`). Evita somar de novo
    /// um arquivo que não pôde ser apagado da pasta.
    var importedFiles: [String] = []
    /// Garrafas que ainda não foram para o Garmin Connect, na ordem do registro
    /// (ver `GarminSync`). Dado antigo, sem o campo, abre com a fila vazia.
    var garminQueue: [GarminPending] = []

    init() {}

    init(settings: Settings, mlByDay: [String: Int], metGoal: [String: Bool],
         importedFiles: [String] = [], garminQueue: [GarminPending] = []) {
        self.settings = settings
        self.mlByDay = mlByDay
        self.metGoal = metGoal
        self.importedFiles = importedFiles
        self.garminQueue = garminQueue
    }

    private enum CodingKeys: String, CodingKey { case settings, mlByDay, metGoal, importedFiles, garminQueue }

    // Decode tolerante: bloco ausente ou ilegível vira o padrão só naquele bloco,
    // sem derrubar os outros (um `metGoal` estranho não pode zerar o histórico).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decodeIfPresent(Settings.self, forKey: .settings)) ?? Settings()
        mlByDay = (try? c.decodeIfPresent([String: Int].self, forKey: .mlByDay)) ?? [:]
        metGoal = (try? c.decodeIfPresent([String: Bool].self, forKey: .metGoal)) ?? [:]
        importedFiles = (try? c.decodeIfPresent([String].self, forKey: .importedFiles)) ?? []
        garminQueue = (try? c.decodeIfPresent([GarminPending].self, forKey: .garminQueue)) ?? []
    }
}

/// Formato antigo, `gota.state.v1`: garrafas por dia. Só é lido, nunca gravado.
/// As primeiras versões do app não tinham `metGoal`, por isso o decode tolerante.
struct LegacyStateV1: Decodable {
    var settings: Settings = Settings()
    var history: [String: Int] = [:]
    var metGoal: [String: Bool] = [:]

    private enum CodingKeys: String, CodingKey { case settings, history, metGoal }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decodeIfPresent(Settings.self, forKey: .settings)) ?? Settings()
        history = (try? c.decodeIfPresent([String: Int].self, forKey: .history)) ?? [:]
        metGoal = (try? c.decodeIfPresent([String: Bool].self, forKey: .metGoal)) ?? [:]
    }
}

/// Decide qual estado carregar a partir do que está gravado. Puro: recebe os bytes
/// das duas chaves e devolve o estado, sem tocar no `UserDefaults`.
enum StateMigration {
    static let v1Key = "gota.state.v1"
    static let v2Key = "gota.state.v2"

    enum Source: Equatable {
        /// Já existia `v2`: nada a migrar.
        case v2
        /// Só existia `v1`: convertido agora. Quem chama deve gravar a `v2`.
        case migratedFromV1
        /// Nada legível gravado: estado padrão.
        case empty
    }

    /// A `v2` sempre vence quando existe e é legível, então rodar de novo depois de
    /// gravar a `v2` não converte outra vez (a migração acontece uma vez só).
    /// A `v1` não é apagada: fica como cópia do dado antigo.
    static func resolve(v2: Data?, v1: Data?) -> (state: PersistedState, source: Source) {
        if let v2, let state = try? JSONDecoder().decode(PersistedState.self, from: v2) {
            return (state, .v2)
        }
        if let v1, let old = try? JSONDecoder().decode(LegacyStateV1.self, from: v1) {
            return (migrate(old), .migratedFromV1)
        }
        return (PersistedState(), .empty)
    }

    /// ml = garrafas × tamanho de garrafa em vigor no momento da migração.
    static func migrate(_ old: LegacyStateV1) -> PersistedState {
        let bottleML = old.settings.bottleML
        return PersistedState(
            settings: old.settings,
            mlByDay: old.history.mapValues { max(0, $0) * bottleML },
            metGoal: old.metGoal
        )
    }
}
