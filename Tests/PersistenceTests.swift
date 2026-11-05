import Foundation
import Testing

private func data(_ json: String) -> Data { Data(json.utf8) }

/// Formato da primeira versão do app: sem `metGoal`, garrafa de 750 ml.
private let v1WithoutMetGoal = """
{"settings":{"bottleML":750,"goalBottles":3,"intervalMin":45,"startHour":9,"endHour":21,"showCountInBar":false},
 "history":{"2026-10-14":1,"2026-10-19":3}}
"""

/// Cópia do `gota.state.v1` real do Vitor em 2026-11-05 (com `metGoal`).
private let v1Real = """
{"history":{"2026-10-30":2,"2026-10-15":2,"2026-10-18":2,"2026-10-20":2,"2026-10-19":3,"2026-10-14":1,"2026-11-03":2,"2026-10-23":1,"2026-10-21":1,"2026-10-16":2},"metGoal":{"2026-10-30":false,"2026-10-15":false,"2026-10-18":false,"2026-10-20":false,"2026-10-19":false,"2026-10-14":false,"2026-11-03":false,"2026-10-23":false,"2026-10-21":false,"2026-10-16":false},"settings":{"bottleML":500,"startHour":8,"showCountInBar":true,"goalBottles":4,"intervalMin":60,"endHour":22}}
"""

@Suite("Migração v1 → v2")
struct MigrationTests {
    @Test func v1WithoutMetGoalKeepsSettingsAndHistory() {
        let (state, source) = StateMigration.resolve(v2: nil, v1: data(v1WithoutMetGoal))
        #expect(source == .migratedFromV1)
        #expect(state.mlByDay == ["2026-10-14": 750, "2026-10-19": 2250])
        #expect(state.metGoal.isEmpty)
        #expect(state.settings == Settings(
            bottleML: 750, goalBottles: 3, intervalMin: 45, startHour: 9, endHour: 21, showCountInBar: false
        ))
    }

    @Test func realV1BecomesBottlesTimesBottleML() {
        let old = try! JSONDecoder().decode(LegacyStateV1.self, from: data(v1Real))
        let (state, source) = StateMigration.resolve(v2: nil, v1: data(v1Real))
        #expect(source == .migratedFromV1)
        #expect(state.mlByDay.count == 10)
        #expect(state.mlByDay == old.history.mapValues { $0 * 500 })
        #expect(state.mlByDay["2026-10-19"] == 1500)
        #expect(state.metGoal == old.metGoal)
        #expect(state.settings == old.settings)
    }

    @Test func nothingSavedGivesDefaults() {
        let (state, source) = StateMigration.resolve(v2: nil, v1: nil)
        #expect(source == .empty)
        #expect(state == PersistedState())
    }

    @Test func unreadableV2FallsBackToV1() {
        let (state, source) = StateMigration.resolve(v2: data("not json"), v1: data(v1Real))
        #expect(source == .migratedFromV1)
        #expect(state.mlByDay.count == 10)
    }

    @Test func missingSettingsFieldKeepsTheOthers() {
        let json = #"{"settings":{"bottleML":600},"history":{"2026-11-01":2}}"#
        let (state, _) = StateMigration.resolve(v2: nil, v1: data(json))
        #expect(state.settings.bottleML == 600)
        #expect(state.settings.goalBottles == Settings().goalBottles)
        #expect(state.mlByDay == ["2026-11-01": 1200])
    }

    @Test func brokenMetGoalDoesNotWipeHistory() {
        let json = #"{"history":{"2026-11-01":2},"metGoal":"oops"}"#
        let (state, _) = StateMigration.resolve(v2: nil, v1: data(json))
        #expect(state.mlByDay == ["2026-11-01": 1000])
        #expect(state.metGoal.isEmpty)
    }
}

@Suite("Migração roda uma vez")
struct IdempotencyTests {
    @Test func savedV2WinsOverV1() throws {
        let (migrated, _) = StateMigration.resolve(v2: nil, v1: data(v1Real))
        let saved = try JSONEncoder().encode(migrated)

        // Segunda abertura: v2 já gravada e v1 ainda lá. Nada é convertido de novo.
        let (again, source) = StateMigration.resolve(v2: saved, v1: data(v1Real))
        #expect(source == .v2)
        #expect(again == migrated)
    }

    @Test func v2IsNotMultipliedAgainAfterBottleChange() throws {
        // Depois de migrar, o Vitor muda a garrafa para 750 ml. Reabrir não pode
        // recalcular o passado com o tamanho novo.
        var (state, _) = StateMigration.resolve(v2: nil, v1: data(v1Real))
        state.settings.bottleML = 750
        let saved = try JSONEncoder().encode(state)

        let (reopened, source) = StateMigration.resolve(v2: saved, v1: data(v1Real))
        #expect(source == .v2)
        #expect(reopened.mlByDay["2026-10-19"] == 1500)
        #expect(reopened.settings.bottleML == 750)
    }

    @Test func v2RoundTripsThroughJSON() throws {
        let state = PersistedState(
            settings: Settings(bottleML: 650),
            mlByDay: ["2026-11-05": 1300],
            metGoal: ["2026-11-04": true]
        )
        let decoded = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}

@Suite("Soma em ml")
struct AddInMLTests {
    @Test func plusOneAddsBottleML() {
        #expect(HydrationLog.ml(0, adding: 1, bottleML: 500) == 500)
        #expect(HydrationLog.ml(1500, adding: 1, bottleML: 750) == 2250)
    }

    @Test func minusOneSubtractsBottleML() {
        #expect(HydrationLog.ml(1500, adding: -1, bottleML: 500) == 1000)
    }

    @Test func neverBelowZero() {
        #expect(HydrationLog.ml(0, adding: -1, bottleML: 500) == 0)
        // Garrafa aumentou depois de registrar: 300 ml − 500 ml para em zero.
        #expect(HydrationLog.ml(300, adding: -1, bottleML: 500) == 0)
    }

    @Test func pastDaysKeepTheirLitersWhenBottleChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14))!
        let mlByDay = ["2026-11-04": 2000, "2026-11-05": 1000]

        let before = HydrationLog(settings: Settings(bottleML: 500), mlByDay: mlByDay,
                                  metGoalByDay: [:], now: now, calendar: calendar)
        let after = HydrationLog(settings: Settings(bottleML: 1000), mlByDay: mlByDay,
                                 metGoalByDay: [:], now: now, calendar: calendar)
        #expect(after.mlByDay["2026-11-04"] == before.mlByDay["2026-11-04"])
        // A tela recalcula as garrafas de hoje com o tamanho atual.
        #expect(before.todayBottles == 2)
        #expect(after.todayBottles == 1)
        #expect(after.todayML == 1000)
    }
}
