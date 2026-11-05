import Foundation

/// Garrafas registradas pelo Atalho do iPhone.
///
/// Cada garrafa é um arquivo na pasta `Gota/inbox` do iCloud Drive, com o horário do
/// registro no nome: `2026-11-05T14-32-00.txt`. O conteúdo do arquivo não importa.
/// Cada arquivo soma uma garrafa (no tamanho de garrafa atual) ao dia do nome, não ao
/// dia em que o Mac leu a pasta.
///
/// É puro: recebe os nomes dos arquivos e o estado, devolve o estado novo e quais
/// arquivos podem ser apagados. Ler e apagar a pasta fica em `PhoneInboxFolder`.
enum PhoneInbox {
    /// Quantos nomes de arquivo já somados ficam guardados. Só servem para o caso de
    /// apagar ter falhado: o arquivo continua na pasta e não pode somar de novo.
    static let rememberedFilesLimit = 200

    /// Dia e horário lidos do nome do arquivo.
    struct Stamp: Equatable {
        /// Chave `yyyy-MM-dd`, a mesma de `mlByDay`.
        let dayKey: String
        let hour: Int
        let minute: Int
        let second: Int
    }

    struct Outcome: Equatable {
        var state: PersistedState
        /// Arquivos já somados que podem sair da pasta: os desta leitura e os que
        /// sobraram de uma leitura anterior em que apagar falhou.
        var filesToDelete: [String]
        /// Garrafas somadas agora (arquivo repetido não conta).
        var addedBottles: Int
        /// Horário de cada garrafa somada agora, em ordem, para a fila do Garmin.
        var addedStamps: [Stamp] = []
    }

    /// Lê `yyyy-MM-ddTHH-mm-ss` do começo do nome. Depois do horário pode vir um
    /// sufixo que não comece por dígito (o iCloud renomeia um repetido para
    /// `2026-11-05T14-32-00 2.txt`) e uma extensão qualquer. Nome fora do formato,
    /// data impossível ou arquivo oculto (começa com ".") devolve `nil`.
    static func stamp(fromFileName fileName: String) -> Stamp? {
        let chars = Array(fileName)
        guard chars.count >= 19 else { return nil }
        let separators: [Int: Character] = [4: "-", 7: "-", 10: "T", 13: "-", 16: "-"]
        for index in 0..<19 {
            if let separator = separators[index] {
                guard chars[index] == separator else { return nil }
            } else {
                guard chars[index].isASCII, chars[index].isNumber else { return nil }
            }
        }
        if chars.count > 19, chars[19].isNumber { return nil }

        func number(_ range: Range<Int>) -> Int { Int(String(chars[range]))! }
        let year = number(0..<4), month = number(5..<7), day = number(8..<10)
        let hour = number(11..<13), minute = number(14..<16), second = number(17..<19)

        guard (1...12).contains(month), (0...23).contains(hour),
              (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(calendar: gregorian, year: year, month: month, day: day)
        guard components.isValidDate else { return nil }

        return Stamp(
            dayKey: String(format: "%04d-%02d-%02d", year, month, day),
            hour: hour, minute: minute, second: second
        )
    }

    /// Soma os arquivos da pasta no estado.
    ///
    /// - Arquivo fora do formato é ignorado e fica na pasta.
    /// - Arquivo já somado antes (está em `importedFiles`) não soma de novo, mas volta
    ///   para a lista de apagar.
    /// - Um dia que passa a bater a meta (com a meta atual) fica marcado como batido
    ///   para o streak. Somar água nunca desmarca um dia já batido.
    static func importing(_ fileNames: [String], into state: PersistedState) -> Outcome {
        var result = state
        var remembered = Set(state.importedFiles)
        var filesToDelete: [String] = []
        var touchedDays = Set<String>()
        var added = 0
        var addedStamps: [Stamp] = []

        for name in fileNames.sorted() {
            guard let stamp = stamp(fromFileName: name) else { continue }
            filesToDelete.append(name)
            guard remembered.insert(name).inserted else { continue }
            result.importedFiles.append(name)
            result.mlByDay[stamp.dayKey] = HydrationLog.ml(
                result.mlByDay[stamp.dayKey] ?? 0, adding: 1, bottleML: state.settings.bottleML
            )
            touchedDays.insert(stamp.dayKey)
            added += 1
            addedStamps.append(stamp)
        }

        let goalML = state.settings.goalBottles * state.settings.bottleML
        for day in touchedDays {
            let met = goalML > 0 && (result.mlByDay[day] ?? 0) >= goalML
            result.metGoal[day] = (result.metGoal[day] ?? false) || met
        }
        result.importedFiles = Array(result.importedFiles.sorted().suffix(rememberedFilesLimit))

        return Outcome(state: result, filesToDelete: filesToDelete, addedBottles: added, addedStamps: addedStamps)
    }
}
