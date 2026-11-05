import Foundation

/// Ajustes do usuário. Os nomes dos campos fazem parte do formato salvo em
/// `gota.state.v1` — renomear quebra o decode do que já está gravado. Campo
/// removido (como `showCountInBar`) é só ignorado no decode.
struct Settings: Codable, Equatable {
    var bottleML: Int = 500
    var goalBottles: Int = 4
    var intervalMin: Int = 60
    var startHour: Int = 8
    var endHour: Int = 22
}
