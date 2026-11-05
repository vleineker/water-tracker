import Foundation

/// Ajustes do usuário. Os nomes dos campos fazem parte do formato salvo
/// (`gota.state.v1` e `gota.state.v2`) — renomear quebra o decode do que já está gravado.
struct Settings: Codable, Equatable {
    var bottleML: Int = 500
    var goalBottles: Int = 4
    var intervalMin: Int = 60
    var startHour: Int = 8
    var endHour: Int = 22
    var showCountInBar: Bool = true
}

// Decode tolerante campo a campo: campo ausente (ex.: um ajuste novo que o dado
// gravado ainda não tem) fica no padrão sem descartar os outros. Ao criar um campo
// novo em `Settings`, acrescentar aqui também. Fica numa extension para manter o
// init memberwise.
extension Settings {
    private enum CodingKeys: String, CodingKey {
        case bottleML, goalBottles, intervalMin, startHour, endHour, showCountInBar
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        bottleML = (try? c.decodeIfPresent(Int.self, forKey: .bottleML)) ?? d.bottleML
        goalBottles = (try? c.decodeIfPresent(Int.self, forKey: .goalBottles)) ?? d.goalBottles
        intervalMin = (try? c.decodeIfPresent(Int.self, forKey: .intervalMin)) ?? d.intervalMin
        startHour = (try? c.decodeIfPresent(Int.self, forKey: .startHour)) ?? d.startHour
        endHour = (try? c.decodeIfPresent(Int.self, forKey: .endHour)) ?? d.endHour
        showCountInBar = (try? c.decodeIfPresent(Bool.self, forKey: .showCountInBar)) ?? d.showCountInBar
    }
}
