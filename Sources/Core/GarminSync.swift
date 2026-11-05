import Foundation

/// Uma garrafa que ainda não foi para o Garmin Connect. Os nomes dos campos fazem
/// parte do formato salvo (`gota.state.v2`, campo `garminQueue`).
struct GarminPending: Codable, Equatable {
    /// Identifica o item para tirá-lo da fila só depois do `ok:true` dele.
    let id: String
    /// Quanto somar no Garmin. Negativo para o "−1".
    let ml: Int
    /// Horário local do registro, `yyyy-MM-ddTHH:mm:ss`, sem fuso: o ajudante grava
    /// no fuso do Mac (ver `garmin/README.md`, comando `add`).
    let localTime: String

    /// Chave `yyyy-MM-dd` do dia do registro, a mesma de `mlByDay`.
    var dayKey: String { String(localTime.prefix(10)) }
}

/// Último total de um dia lido do Garmin (`get`). Os nomes dos campos fazem parte do
/// formato salvo (`gota.state.v2`, campo `garminLastRead`).
struct GarminRead: Codable, Equatable {
    let dayKey: String
    let ml: Int
}

/// O que pediu a sincronização. Só as agendadas passam por cima da espera depois de
/// um erro de "tento de novo mais tarde".
enum GarminTrigger: Equatable {
    /// Abertura do app e o relógio de 15 min.
    case scheduled
    /// O interruptor acabou de ser ligado.
    case switchedOn
    case panelOpened
    /// Logo depois de uma garrafa somada ou removida.
    case bottle
}

/// O que deu errado numa chamada ao ajudante, decidido pelo `code` do JSON (nunca
/// pela `message`, que pode mudar) ou pela falta do `node`/do ajudante no Mac.
enum GarminProblem: Equatable {
    /// `auth_required`: falta rodar o login no Terminal.
    case sessionMissing
    /// `network`
    case offline
    /// `rate_limited`
    case rateLimited
    /// `garmin_unavailable`
    case garminDown
    /// `garmin_changed`
    case helperOutdated
    /// Nem `/opt/homebrew/bin/node` nem `/usr/local/bin/node`.
    case nodeMissing
    /// O `.app` não traz `Resources/garmin/gota-garmin.mjs`.
    case helperMissing
    /// `usage`, `internal`, código desconhecido ou resposta ilegível.
    case helperFailed

    init(code: String) {
        switch code {
        case "auth_required": self = .sessionMissing
        case "network": self = .offline
        case "rate_limited": self = .rateLimited
        case "garmin_unavailable": self = .garminDown
        case "garmin_changed": self = .helperOutdated
        default: self = .helperFailed
        }
    }

    /// Texto da linha discreta do painel.
    var message: String {
        switch self {
        case .sessionMissing: return "Garmin sem sessão. Rode o login no Terminal:"
        case .offline: return "Sem conexão com o Garmin. Tento de novo mais tarde."
        case .rateLimited: return "O Garmin pediu uma pausa. Tento de novo mais tarde."
        case .garminDown: return "O Garmin Connect está fora do ar. Tento de novo mais tarde."
        case .helperOutdated: return "O Garmin mudou e o ajudante precisa de atualização."
        case .nodeMissing: return "Garmin: Node não encontrado. Instale com brew install node."
        case .helperMissing: return "O ajudante do Garmin não está no app. Reinstale com ./build.sh."
        case .helperFailed: return "Erro no ajudante do Garmin. Tento de novo mais tarde."
        }
    }

    /// Erros em que tentar de novo logo não adianta (ou piora, como o 429): esperam a
    /// próxima sincronização agendada. Os outros dependem de algo que o Vitor resolve
    /// (login, instalar o Node), então abrir o painel já tenta de novo.
    var waitsForSchedule: Bool {
        switch self {
        case .offline, .rateLimited, .garminDown, .helperOutdated, .helperFailed: return true
        case .sessionMissing, .nodeMissing, .helperMissing: return false
        }
    }
}

/// Resposta de uma execução do ajudante (`get` ou `add`).
enum GarminReply: Equatable {
    /// `ml` do `get`, ou `total_ml` do `add`.
    case ok(ml: Int?)
    case failed(GarminProblem)

    private struct Wire: Decodable {
        struct Failure: Decodable { let code: String }
        let ok: Bool
        let ml: Int?
        let total_ml: Int?
        let error: Failure?
    }

    /// Lê a saída padrão do ajudante: uma linha JSON (contrato em `garmin/README.md`).
    /// Usa a última linha não vazia. Saída ilegível vira `helperFailed`.
    static func parse(_ stdout: String) -> GarminReply {
        let line = stdout.split(whereSeparator: \.isNewline).last { !$0.allSatisfy(\.isWhitespace) }
        guard let line, let wire = try? JSONDecoder().decode(Wire.self, from: Data(line.utf8)) else {
            return .failed(.helperFailed)
        }
        if wire.ok { return .ok(ml: wire.ml ?? wire.total_ml) }
        return .failed(GarminProblem(code: wire.error?.code ?? ""))
    }
}

/// Regras da sincronização com o Garmin Connect. Pura: a chamada ao `node` fica em
/// `GarminSyncer`, fora do núcleo.
enum GarminSync {
    /// Intervalo da sincronização agendada.
    static let interval: TimeInterval = 15 * 60
    /// Abrir o painel várias vezes seguidas não repete a leitura do Garmin.
    static let panelMinimumGap: TimeInterval = 60

    /// Horário local `yyyy-MM-ddTHH:mm:ss` de `date` no calendário dado.
    static func localTime(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Item da fila para uma mudança feita no Mac. `ml` é a diferença real do dia
    /// (o "−1" que parou no zero manda só o que saiu). Sem diferença, sem item.
    static func pending(ml: Int, at date: Date, calendar: Calendar, id: String) -> GarminPending? {
        guard ml != 0 else { return nil }
        return GarminPending(id: id, ml: ml, localTime: localTime(for: date, calendar: calendar))
    }

    /// Item da fila para uma garrafa do Atalho do iPhone, no horário do nome do arquivo.
    static func pending(from stamp: PhoneInbox.Stamp, ml: Int, id: String) -> GarminPending {
        GarminPending(
            id: id, ml: ml,
            localTime: String(format: "%@T%02d:%02d:%02d", stamp.dayKey, stamp.hour, stamp.minute, stamp.second)
        )
    }

    /// Registro único ao ligar o interruptor, para o que já estava no Gota hoje não
    /// sumir quando o total passar a vir do Garmin.
    ///
    /// Regra: manda o ml de hoje menos o que o Garmin já tem dele (o último total de
    /// hoje lido de lá; outro dia ou nenhuma leitura = 0) menos o que de hoje ainda
    /// está na fila. Desligar e ligar de novo no mesmo dia só manda o que mudou com o
    /// interruptor desligado (um "−1" nesse meio vira registro negativo). Dias
    /// anteriores nunca vão.
    static func catchUp(
        todayML: Int, todayKey: String, lastRead: GarminRead?, queue: [GarminPending],
        at date: Date, calendar: Calendar, id: String
    ) -> GarminPending? {
        let confirmed = lastRead.map { $0.dayKey == todayKey ? $0.ml : 0 } ?? 0
        let pending = queue.filter { $0.dayKey == todayKey }.reduce(0) { $0 + $1.ml }
        return self.pending(ml: todayML - confirmed - pending, at: date, calendar: calendar, id: id)
    }

    /// Fila depois de enviar o item `id`: ele só sai com `ok:true`.
    static func queue(_ queue: [GarminPending], afterSending id: String, reply: GarminReply) -> [GarminPending] {
        guard case .ok = reply else { return queue }
        return queue.filter { $0.id != id }
    }

    /// Total de hoje com o interruptor ligado: o que o Garmin confirmou mais o que de
    /// hoje ainda está na fila. Nunca abaixo de zero.
    static func todayTotal(garminML: Int, queue: [GarminPending], todayKey: String) -> Int {
        let pending = queue.filter { $0.dayKey == todayKey }.reduce(0) { $0 + $1.ml }
        return max(0, garminML + pending)
    }

    /// Até quando esperar depois de um erro (nil = não esperar).
    static func retryAfter(_ problem: GarminProblem, now: Date) -> Date? {
        problem.waitsForSchedule ? now.addingTimeInterval(interval) : nil
    }

    /// Decide se uma sincronização pedida agora deve rodar.
    static func shouldRun(
        _ trigger: GarminTrigger, enabled: Bool, now: Date,
        retryAfter: Date?, lastSuccess: Date?, queueIsEmpty: Bool
    ) -> Bool {
        guard enabled else { return false }
        switch trigger {
        case .scheduled, .switchedOn:
            return true
        case .panelOpened, .bottle:
            if let retryAfter, now < retryAfter { return false }
            if trigger == .panelOpened, queueIsEmpty, let lastSuccess,
               now.timeIntervalSince(lastSuccess) < panelMinimumGap {
                return false
            }
            return true
        }
    }
}
