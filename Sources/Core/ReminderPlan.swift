import Foundation

/// Regras do lembrete: ele só toca quando o dia está atrás do ritmo da meta.
///
/// Ritmo esperado num instante = meta × fração da janela (início–fim) já passada.
/// O dia fica atrasado no instante em que o esperado alcança o que já foi bebido
/// (com nada bebido, isso é o início da janela). O lembrete toca nesse instante,
/// ou depois se o espaço mínimo desde o último aviso (ou a última garrafa) ainda
/// não passou. Nunca fora da janela, nunca com a meta do dia batida.
///
/// Como o resto do núcleo, é puro: o instante de referência chega por parâmetro
/// (`HydrationLog.now` não é usado aqui, porque o store passa o início do dia nele).
extension HydrationLog {
    /// Início e fim da janela ativa no dia de `date`. Calculado pelo relógio de
    /// parede do calendário, então a janela segue 08:00–22:00 mesmo em dia de
    /// horário de verão (o dia só fica uma hora mais curto ou mais longo).
    func activeWindow(on date: Date) -> (start: Date, end: Date)? {
        guard let start = calendar.date(bySettingHour: settings.startHour, minute: 0, second: 0, of: date),
              let end = calendar.date(bySettingHour: settings.endHour, minute: 0, second: 0, of: date),
              start < end else { return nil }
        return (start, end)
    }

    /// Instante em que o dia de `date` passa a ficar atrás do ritmo, dado o que foi
    /// bebido naquele dia. `nil` com a meta batida (ou meta zero).
    func paceCrossing(on date: Date) -> Date? {
        guard goalML > 0, let window = activeWindow(on: date) else { return nil }
        let drunk = mlByDay[Self.dayKey(for: date, calendar: calendar)] ?? 0
        guard drunk < goalML else { return nil }
        let fraction = Double(drunk) / Double(goalML)
        return window.start.addingTimeInterval(fraction * window.end.timeIntervalSince(window.start))
    }

    /// Próximo lembrete a partir de `date`, nunca antes de `notBefore`. Se não cabe
    /// mais nada no dia (meta batida, janela encerrada), vai para o dia seguinte,
    /// em que nada foi bebido ainda.
    func nextReminder(after date: Date, notBefore: Date? = nil) -> Date? {
        let floor = max(date, notBefore ?? date)
        let firstDay = calendar.startOfDay(for: floor)
        for offset in 0..<2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  let window = activeWindow(on: day),
                  let crossing = paceCrossing(on: day) else { continue }
            let candidate = max(crossing, floor)
            if candidate < window.end { return candidate }
        }
        return nil
    }

    /// Lembretes a agendar no sistema, supondo que nada mude até lá: o primeiro e,
    /// se o Vitor não beber, os seguintes espaçados por `minimumGap`. Qualquer
    /// garrafa ou ajuste refaz a lista, então os seguintes só tocam se ele seguir atrasado.
    ///
    /// - `lastReminderAt`: último lembrete entregue; o próximo espera `minimumGap` dele.
    /// - `lastDrinkAt`: última garrafa somada; também espera `minimumGap` dela, para
    ///   não lembrar logo depois de beber quando ainda falta para o ritmo.
    /// - `snoozedUntil`: "Lembrar em 15 min" posterior ao último lembrete; vale no
    ///   lugar do espaço mínimo desde o último lembrete.
    func upcomingReminders(
        after date: Date,
        lastReminderAt: Date?,
        lastDrinkAt: Date?,
        snoozedUntil: Date?,
        minimumGap: TimeInterval,
        limit: Int
    ) -> [Date] {
        let gap = max(minimumGap, 1)
        let reminderFloor: Date?
        if let snoozedUntil, snoozedUntil > (lastReminderAt ?? .distantPast) {
            reminderFloor = snoozedUntil
        } else {
            reminderFloor = lastReminderAt.map { $0.addingTimeInterval(gap) }
        }
        let drinkFloor = lastDrinkAt.map { $0.addingTimeInterval(gap) }
        var notBefore = [reminderFloor, drinkFloor].compactMap { $0 }.max()

        var result: [Date] = []
        while result.count < limit, let next = nextReminder(after: date, notBefore: notBefore) {
            result.append(next)
            notBefore = next.addingTimeInterval(gap)
        }
        return result
    }
}
