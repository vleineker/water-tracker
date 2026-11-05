import Foundation
import Testing

/// Calendário fixo (gregoriano, São Paulo) para os testes não dependerem da máquina.
private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return c
}()

/// 2026-11-05 às 14:00 em São Paulo.
private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14))!

private func key(daysAgo: Int) -> String {
    HydrationLog.dayKey(for: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, calendar: calendar)
}

/// Meta padrão: 4 garrafas de 500 ml (2 L).
private func makeLog(
    todayBottles: Int,
    settings: Settings = Settings(),
    pastMet: [Int] = [],
    staleTodayFlag: Bool? = nil
) -> HydrationLog {
    var met: [String: Bool] = [:]
    for daysAgo in pastMet { met[key(daysAgo: daysAgo)] = true }
    if let staleTodayFlag { met[key(daysAgo: 0)] = staleTodayFlag }
    return HydrationLog(
        settings: settings,
        mlByDay: [key(daysAgo: 0): todayBottles * settings.bottleML],
        metGoalByDay: met,
        now: now,
        calendar: calendar
    )
}

@Suite("Hoje")
struct TodayTests {
    @Test func dayKeyUsesCalendarTimeZone() {
        #expect(HydrationLog.dayKey(for: now, calendar: calendar) == "2026-11-05")
        // 23:30 em São Paulo já é dia 6 em UTC, mas a chave segue o calendário dado.
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 23, minute: 30))!
        #expect(HydrationLog.dayKey(for: lateNight, calendar: calendar) == "2026-11-05")
    }

    @Test func bottlesComeFromML() {
        let log = makeLog(todayBottles: 3)
        #expect(log.todayML == 1500)
        #expect(log.todayBottles == 3)
        #expect(log.goalML == 2000)
    }

    @Test func emptyDay() {
        let log = HydrationLog(settings: Settings(), mlByDay: [:], metGoalByDay: [:], now: now, calendar: calendar)
        #expect(log.todayBottles == 0)
        #expect(log.progress == 0)
        #expect(!log.metGoalToday)
    }
}

@Suite("Progresso")
struct ProgressTests {
    @Test(arguments: [(0, 0.0), (1, 0.25), (2, 0.5), (4, 1.0), (6, 1.0)])
    func progressIsCappedAtOne(bottles: Int, expected: Double) {
        #expect(makeLog(todayBottles: bottles).progress == expected)
    }

    @Test func zeroGoalNeverDividesByZero() {
        var s = Settings()
        s.goalBottles = 0
        let log = makeLog(todayBottles: 2, settings: s)
        #expect(log.progress == 0)
        #expect(!log.metGoalToday)
    }
}

@Suite("Meta batida")
struct GoalTests {
    @Test func belowAndAtGoal() {
        #expect(!makeLog(todayBottles: 3).metGoalToday)
        #expect(makeLog(todayBottles: 4).metGoalToday)
        #expect(makeLog(todayBottles: 5).metGoalToday)
    }

    @Test func loweringTheGoalCountsImmediately() {
        // O bug da issue #2: 3 garrafas, meta reduzida de 4 para 3, sem tocar em +1/−1.
        var lowered = Settings()
        lowered.goalBottles = 3
        #expect(!makeLog(todayBottles: 3).metGoalToday)
        #expect(makeLog(todayBottles: 3, settings: lowered).metGoalToday)
    }

    @Test func raisingTheGoalUndoesToday() {
        var raised = Settings()
        raised.goalBottles = 5
        #expect(!makeLog(todayBottles: 4, settings: raised).metGoalToday)
    }

    @Test func todayIgnoresStaleSavedFlag() {
        // Um `true` gravado com a meta antiga não vale contra o total atual.
        #expect(!makeLog(todayBottles: 2, staleTodayFlag: true).metGoalToday)
        #expect(makeLog(todayBottles: 4, staleTodayFlag: false).metGoalToday)
    }
}

@Suite("Streak")
struct StreakTests {
    @Test func countsBackFromYesterday() {
        #expect(makeLog(todayBottles: 0, pastMet: [1, 2, 3]).streak == 3)
    }

    @Test func todayAddsOneWhenMet() {
        #expect(makeLog(todayBottles: 4, pastMet: [1, 2, 3]).streak == 4)
    }

    @Test func undoAfterMeetingGoalRemovesToday() {
        // Bateu 4/4 (streak 4), depois "−1" volta para 3/4: hoje deixa de contar.
        let met = makeLog(todayBottles: 4, pastMet: [1, 2, 3], staleTodayFlag: true)
        let undone = makeLog(todayBottles: 3, pastMet: [1, 2, 3], staleTodayFlag: true)
        #expect(met.streak == 4)
        #expect(undone.streak == 3)
        #expect(undone.last7Days.last?.met == false)
    }

    @Test func gapBreaksTheStreak() {
        #expect(makeLog(todayBottles: 0, pastMet: [1, 3, 4]).streak == 1)
        #expect(makeLog(todayBottles: 0, pastMet: [2, 3]).streak == 0)
        #expect(makeLog(todayBottles: 4, pastMet: [2, 3]).streak == 1)
    }

    @Test func runsPastSevenDays() {
        #expect(makeLog(todayBottles: 0, pastMet: Array(1...10)).streak == 10)
    }
}

@Suite("Últimos 7 dias")
struct Last7DaysTests {
    @Test func sevenDaysEndingToday() {
        let days = makeLog(todayBottles: 4, pastMet: [1, 3]).last7Days
        #expect(days.map(\.id) == (0...6).reversed().map { key(daysAgo: $0) })
        #expect(days.map(\.met) == [false, false, false, true, false, true, true])
        #expect(days.map(\.isToday) == [false, false, false, false, false, false, true])
    }

    @Test func crossesMonthBoundary() {
        let first = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9))!
        let log = HydrationLog(settings: Settings(), mlByDay: [:], metGoalByDay: [:], now: first, calendar: calendar)
        #expect(log.last7Days.first?.id == "2026-02-23")
        #expect(log.last7Days.last?.id == "2026-03-01")
    }
}

@Suite("Validação de início e fim")
struct ValidationTests {
    private func with(start: Int, end: Int) -> Settings {
        var s = Settings()
        s.startHour = start
        s.endHour = end
        return s
    }

    @Test func validChangesPassThrough() {
        let current = with(start: 8, end: 22)
        #expect(HydrationLog.validated(with(start: 9, end: 22), from: current) == with(start: 9, end: 22))
        #expect(HydrationLog.validated(with(start: 8, end: 20), from: current) == with(start: 8, end: 20))
    }

    @Test func startCannotReachEnd() {
        let current = with(start: 21, end: 22)
        #expect(HydrationLog.validated(with(start: 22, end: 22), from: current).startHour == 21)
        #expect(HydrationLog.validated(with(start: 23, end: 22), from: current).startHour == 21)
    }

    @Test func endCannotReachStart() {
        let current = with(start: 8, end: 9)
        #expect(HydrationLog.validated(with(start: 8, end: 8), from: current).endHour == 9)
        #expect(HydrationLog.validated(with(start: 8, end: 3), from: current).endHour == 9)
    }

    @Test func hoursStayInsideTheDay() {
        #expect(HydrationLog.validated(with(start: -1, end: 22), from: with(start: 0, end: 22)).startHour == 0)
        #expect(HydrationLog.validated(with(start: 8, end: 24), from: with(start: 8, end: 23)).endHour == 23)
    }

    @Test func otherFieldsAreUntouched() {
        var proposed = Settings()
        proposed.goalBottles = 7
        proposed.bottleML = 750
        #expect(HydrationLog.validated(proposed, from: Settings()) == proposed)
    }
}
