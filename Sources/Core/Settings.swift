import Foundation

/// Ajustes do usuário. Os nomes dos campos fazem parte do formato salvo
/// (`gota.state.v1` e `gota.state.v2`) — renomear quebra o decode do que já está gravado.
/// Campo removido (como `showCountInBar`) é só ignorado no decode.
struct Settings: Codable, Equatable {
    var bottleML: Int = 500
    var goalBottles: Int = 4
    var intervalMin: Int = 60
    var startHour: Int = 8
    var endHour: Int = 22
    /// Envia cada garrafa ao Garmin Connect e lê de lá o total de hoje. Desligado de fábrica.
    var garminEnabled: Bool = false
}

// Decode tolerante campo a campo: campo ausente (ex.: um ajuste novo que o dado
// gravado ainda não tem) fica no padrão sem descartar os outros. Ao criar um campo
// novo em `Settings`, acrescentar aqui também. Fica numa extension para manter o
// init memberwise.
extension Settings {
    private enum CodingKeys: String, CodingKey {
        case bottleML, goalBottles, intervalMin, startHour, endHour, garminEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        bottleML = (try? c.decodeIfPresent(Int.self, forKey: .bottleML)) ?? d.bottleML
        goalBottles = (try? c.decodeIfPresent(Int.self, forKey: .goalBottles)) ?? d.goalBottles
        intervalMin = (try? c.decodeIfPresent(Int.self, forKey: .intervalMin)) ?? d.intervalMin
        startHour = (try? c.decodeIfPresent(Int.self, forKey: .startHour)) ?? d.startHour
        endHour = (try? c.decodeIfPresent(Int.self, forKey: .endHour)) ?? d.endHour
        garminEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .garminEnabled)) ?? d.garminEnabled
    }
}
