import Foundation

/// Um dia na faixa de streak (D-6 … hoje) — ver regra do streak no handoff de design.
struct StreakDay: Identifiable, Equatable {
    let id: String
    let met: Bool
    let isToday: Bool
}

/// Núcleo das regras de hidratação: única fonte de "quanto bebi hoje", progresso,
/// meta batida, streak e validação dos ajustes.
///
/// É puro: não lê relógio, disco nem singletons. Tudo chega por parâmetro, então
/// o mesmo valor de entrada dá sempre o mesmo resultado (é o que os testes usam).
struct HydrationLog {
    let settings: Settings
    /// Quanto foi bebido em cada dia, em ml, pela chave `yyyy-MM-dd`.
    let mlByDay: [String: Int]
    /// Resultado gravado de dias anteriores. O de hoje é sempre recalculado a partir
    /// de `mlByDay` e da meta atual, nunca lido daqui.
    let metGoalByDay: [String: Bool]
    let now: Date
    let calendar: Calendar

    // MARK: - Hoje

    var todayKey: String { Self.dayKey(for: now, calendar: calendar) }

    var todayML: Int { mlByDay[todayKey] ?? 0 }

    var goalML: Int { settings.goalBottles * settings.bottleML }

    var todayBottles: Int {
        guard settings.bottleML > 0 else { return 0 }
        return todayML / settings.bottleML
    }

    /// De 0 a 1, travado em 1 quando passa da meta.
    var progress: Double {
        guard goalML > 0 else { return 0 }
        return min(1.0, Double(todayML) / Double(goalML))
    }

    /// Vale o total atual do dia, não "em algum momento": um "−1" depois de bater
    /// a meta desfaz o dia batido (regra do streak, handoff seção 4).
    var metGoalToday: Bool {
        goalML > 0 && todayML >= goalML
    }

    // MARK: - Streak

    /// Dias consecutivos com meta batida terminando ontem, mais hoje se hoje já bateu.
    var streak: Int {
        var count = metGoalToday ? 1 : 0
        var offset = 1
        while let day = calendar.date(byAdding: .day, value: -offset, to: now),
              metGoalByDay[Self.dayKey(for: day, calendar: calendar)] == true {
            count += 1
            offset += 1
        }
        return count
    }

    /// Últimos 7 dias (D-6 … hoje) para a faixa de pontos do streak.
    var last7Days: [StreakDay] {
        stride(from: 6, through: 0, by: -1).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = Self.dayKey(for: day, calendar: calendar)
            let met = offset == 0 ? metGoalToday : (metGoalByDay[key] ?? false)
            return StreakDay(id: key, met: met, isToday: offset == 0)
        }
    }

    // MARK: - Regras gerais

    /// Chave `yyyy-MM-dd` do dia de `date` no calendário dado.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// ml do dia depois de "+1 garrafa" (`delta` 1) ou "−1" (`delta` −1): soma ou
    /// subtrai `bottleML` por garrafa, sem passar abaixo de zero.
    static func ml(_ currentML: Int, adding delta: Int, bottleML: Int) -> Int {
        max(0, currentML + delta * bottleML)
    }

    /// Ajustes propostos corrigidos para uma janela válida: início sempre antes do fim,
    /// dentro de 0–23. O campo que mudou é o que cede: subir o início até o fim trava
    /// o início uma hora antes; baixar o fim até o início trava o fim uma hora depois.
    static func validated(_ proposed: Settings, from current: Settings) -> Settings {
        var result = proposed
        if result.startHour != current.startHour {
            result.startHour = max(0, min(result.startHour, result.endHour - 1))
        }
        if result.endHour != current.endHour {
            result.endHour = min(23, max(result.endHour, result.startHour + 1))
        }
        return result
    }
}
