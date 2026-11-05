import Foundation
import Testing

/// Janela padrão 08:00–22:00 (14 h), meta 4 × 500 ml, espaço mínimo de 60 min.
/// Com 1 garrafa bebida, o ritmo alcança o bebido 3h30 depois do início (11:30);
/// com 2, às 15:00; com 3, às 18:30.
private let saoPaulo: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return c
}()

/// Fuso com horário de verão: em 2026 adianta 1 h em 8 de março, às 02:00.
private let newYork: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private let hour: TimeInterval = 3600
private let gap: TimeInterval = 60 * 60

private func at(_ h: Int, _ m: Int = 0, day: Int = 5, month: Int = 11, calendar: Calendar = saoPaulo) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: h, minute: m))!
}

private func log(
    bottles: Int,
    on date: Date = at(12),
    settings: Settings = Settings(),
    calendar: Calendar = saoPaulo
) -> HydrationLog {
    HydrationLog(
        settings: settings,
        mlByDay: [HydrationLog.dayKey(for: date, calendar: calendar): bottles * settings.bottleML],
        metGoalByDay: [:],
        now: calendar.startOfDay(for: date),
        calendar: calendar
    )
}

private func plan(
    _ log: HydrationLog,
    from date: Date,
    lastReminderAt: Date? = nil,
    lastDrinkAt: Date? = nil,
    snoozedUntil: Date? = nil,
    limit: Int = 1
) -> [Date] {
    log.upcomingReminders(
        after: date,
        lastReminderAt: lastReminderAt,
        lastDrinkAt: lastDrinkAt,
        snoozedUntil: snoozedUntil,
        minimumGap: gap,
        limit: limit
    )
}

@Suite("Lembrete: janela")
struct ReminderWindowTests {
    @Test func beforeWindowWaitsForStart() {
        #expect(plan(log(bottles: 0), from: at(6)) == [at(8)])
    }

    @Test func drinkBeforeWindowCountsForThePace() {
        #expect(plan(log(bottles: 1), from: at(7)) == [at(11, 30)])
    }

    @Test func afterWindowGoesToTomorrowStart() {
        #expect(plan(log(bottles: 1), from: at(22, 30)) == [at(8, day: 6)])
    }

    @Test func goalMetSkipsTheRestOfToday() {
        #expect(plan(log(bottles: 4), from: at(14)) == [at(8, day: 6)])
        #expect(plan(log(bottles: 6), from: at(9)) == [at(8, day: 6)])
    }
}

@Suite("Lembrete: ritmo")
struct ReminderPaceTests {
    @Test func onPaceWaitsUntilFallingBehind() {
        // 14:00, esperado ~857 ml, bebido 1000 ml: em dia até as 15:00.
        #expect(plan(log(bottles: 2), from: at(14)) == [at(15)])
    }

    @Test func behindRemindsNow() {
        // 14:00, esperado ~857 ml, bebido 500 ml.
        #expect(plan(log(bottles: 1), from: at(14)) == [at(14)])
    }

    @Test func lastBottleOfTheDay() {
        #expect(plan(log(bottles: 3), from: at(14)) == [at(18, 30)])
    }
}

@Suite("Lembrete: espaço mínimo")
struct ReminderGapTests {
    @Test func waitsMinimumGapSinceLastReminder() {
        #expect(plan(log(bottles: 1), from: at(14), lastReminderAt: at(13, 30)) == [at(14, 30)])
    }

    @Test func oldReminderDoesNotDelay() {
        #expect(plan(log(bottles: 1), from: at(14), lastReminderAt: at(12)) == [at(14)])
    }

    @Test func gapPastWindowEndGoesToTomorrow() {
        #expect(plan(log(bottles: 1), from: at(21, 30), lastReminderAt: at(21, 15)) == [at(8, day: 6)])
    }

    @Test func noReminderRightAfterDrinkingEvenIfStillBehind() {
        #expect(plan(log(bottles: 1), from: at(14), lastDrinkAt: at(13, 50)) == [at(14, 50)])
    }

    @Test func pacePointLaterThanGapWins() {
        #expect(plan(log(bottles: 2), from: at(14), lastReminderAt: at(13, 30)) == [at(15)])
    }

    @Test func snoozeReplacesGapSinceLastReminder() {
        #expect(plan(log(bottles: 1), from: at(14), lastReminderAt: at(14), snoozedUntil: at(14, 15)) == [at(14, 15)])
    }

    @Test func snoozeStillRespectsLastDrink() {
        #expect(plan(
            log(bottles: 1), from: at(14, 5),
            lastReminderAt: at(14), lastDrinkAt: at(14, 5), snoozedUntil: at(14, 15)
        ) == [at(15, 5)])
    }

    @Test func staleSnoozeIsIgnored() {
        // Lembrete adiado já entregue (último lembrete = horário do adiamento).
        #expect(plan(log(bottles: 1), from: at(14, 20), lastReminderAt: at(14, 15), snoozedUntil: at(14, 15)) == [at(15, 15)])
    }

    @Test func followUpsAreSpacedByTheGap() {
        #expect(plan(log(bottles: 1), from: at(14), limit: 4) == [at(14), at(15), at(16), at(17)])
    }
}

@Suite("Lembrete: virada do dia e horário de verão")
struct ReminderCalendarTests {
    @Test func followUpsRollOverToTomorrowWithNothingDrunk() {
        #expect(plan(log(bottles: 1), from: at(20), limit: 4) == [at(20), at(21), at(8, day: 6), at(9, day: 6)])
    }

    @Test func goalMetTodayDoesNotCarryIntoTomorrow() {
        let today = log(bottles: 4)
        #expect(plan(today, from: at(23, 59), limit: 2) == [at(8, day: 6), at(9, day: 6)])
    }

    @Test func windowStartFollowsWallClockAcrossDST() {
        // 23:00 de 7/3 (EST) até 08:00 de 8/3 (EDT): 8 h reais, não 9.
        let evening = at(23, day: 7, month: 3, calendar: newYork)
        let reminders = plan(log(bottles: 4, on: evening, calendar: newYork), from: evening)
        #expect(reminders == [at(8, day: 8, month: 3, calendar: newYork)])
        #expect(newYork.component(.hour, from: reminders[0]) == 8)
        #expect(reminders[0].timeIntervalSince(evening) == 8 * hour)
    }

    @Test func paceUsesRealHoursOnShortDSTDay() {
        // Janela 00:00–04:00 em 8/3 tem só 3 h reais; metade da meta vale 1h30 depois do início.
        var s = Settings()
        s.startHour = 0
        s.endHour = 4
        let start = at(0, day: 8, month: 3, calendar: newYork)
        let reminders = plan(log(bottles: 2, on: start, settings: s, calendar: newYork), from: start)
        #expect(reminders == [start.addingTimeInterval(1.5 * hour)])
    }
}
