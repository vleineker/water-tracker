import Foundation
import Testing

private let saoPaulo: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return c
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    saoPaulo.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
}

private func item(_ id: String, _ ml: Int, _ localTime: String) -> GarminPending {
    GarminPending(id: id, ml: ml, localTime: localTime)
}

@Suite("Fila do Garmin")
struct GarminQueueTests {
    @Test func plusOneQueuesBottleWithLocalTime() {
        let before = 1000
        let after = HydrationLog.ml(before, adding: 1, bottleML: 500)
        let entry = GarminSync.pending(ml: after - before, at: at(5, 14, 32, 7), calendar: saoPaulo, id: "a")
        #expect(entry == item("a", 500, "2026-11-05T14:32:07"))
        #expect(entry?.dayKey == "2026-11-05")
    }

    @Test func minusOneQueuesNegative() {
        let after = HydrationLog.ml(1000, adding: -1, bottleML: 500)
        let entry = GarminSync.pending(ml: after - 1000, at: at(5, 9), calendar: saoPaulo, id: "b")
        #expect(entry?.ml == -500)
    }

    @Test func minusOneStoppedAtZeroSendsOnlyWhatLeft() {
        // Garrafa aumentou para 500 ml com 300 ml no dia: o dia vai a 0, saem 300.
        let after = HydrationLog.ml(300, adding: -1, bottleML: 500)
        #expect(GarminSync.pending(ml: after - 300, at: at(5, 9), calendar: saoPaulo, id: "c")?.ml == -300)
    }

    @Test func noChangeQueuesNothing() {
        let after = HydrationLog.ml(0, adding: -1, bottleML: 500)
        #expect(GarminSync.pending(ml: after - 0, at: at(5, 9), calendar: saoPaulo, id: "d") == nil)
    }

    @Test func phoneBottleFromYesterdayKeepsItsDayAndTime() {
        let outcome = PhoneInbox.importing(["2026-11-04T23-58-09.txt"], into: PersistedState())
        #expect(outcome.addedStamps.count == 1)
        let entry = GarminSync.pending(from: outcome.addedStamps[0], ml: 500, id: "e")
        #expect(entry == item("e", 500, "2026-11-04T23:58:09"))
        #expect(entry.dayKey == "2026-11-04")
    }

    @Test func repeatedPhoneFileQueuesNothing() {
        var state = PersistedState()
        state.importedFiles = ["2026-11-05T08-00-00.txt"]
        let outcome = PhoneInbox.importing(["2026-11-05T08-00-00.txt"], into: state)
        #expect(outcome.addedStamps.isEmpty)
    }

    @Test func itemLeavesOnlyAfterOk() {
        let queue = [item("a", 500, "2026-11-05T08:00:00"), item("b", 500, "2026-11-05T09:00:00")]
        #expect(GarminSync.queue(queue, afterSending: "a", reply: .failed(.offline)) == queue)
        #expect(GarminSync.queue(queue, afterSending: "a", reply: .failed(.sessionMissing)) == queue)
        #expect(GarminSync.queue(queue, afterSending: "a", reply: .ok(ml: 500)) == [queue[1]])
    }

    @Test func okKeepsItemsAddedDuringTheSend() {
        // Garrafa nova entrou na fila enquanto "a" era enviado: ela fica.
        let queue = [item("a", 500, "2026-11-05T08:00:00"), item("new", 500, "2026-11-05T08:00:05")]
        #expect(GarminSync.queue(queue, afterSending: "a", reply: .ok(ml: nil)).map(\.id) == ["new"])
    }

    @Test func todayIsGarminPlusTodaysQueue() {
        let queue = [
            item("y", 500, "2026-11-04T22:00:00"),
            item("a", 500, "2026-11-05T08:00:00"),
            item("b", -500, "2026-11-05T09:00:00"),
            item("c", 750, "2026-11-05T10:00:00"),
        ]
        #expect(GarminSync.todayTotal(garminML: 1250, queue: queue, todayKey: "2026-11-05") == 2000)
        #expect(GarminSync.todayTotal(garminML: 1250, queue: [], todayKey: "2026-11-05") == 1250)
    }

    @Test func todayNeverBelowZero() {
        let queue = [item("a", -500, "2026-11-05T08:00:00")]
        #expect(GarminSync.todayTotal(garminML: 200, queue: queue, todayKey: "2026-11-05") == 0)
    }
}

@Suite("Ligar o Garmin no meio do dia")
struct GarminCatchUpTests {
    let today = "2026-11-05"

    private func catchUp(_ todayML: Int, lastRead: GarminRead? = nil, queue: [GarminPending] = []) -> GarminPending? {
        GarminSync.catchUp(todayML: todayML, todayKey: today, lastRead: lastRead, queue: queue,
                           at: at(5, 15), calendar: saoPaulo, id: "seed")
    }

    @Test func bottlesAlreadyTodayGoAsOneEntryNow() {
        let seed = catchUp(1000)
        #expect(seed == item("seed", 1000, "2026-11-05T15:00:00"))
        // Primeira leitura: Garmin com 0 e o registro único ainda na fila → nada some.
        #expect(GarminSync.todayTotal(garminML: 0, queue: [seed!], todayKey: today) == 1000)
    }

    @Test func emptyDaySendsNothing() {
        #expect(catchUp(0) == nil)
    }

    @Test func switchingOffAndOnAgainDoesNotResend() {
        // Ligou, mandou 1000 e leu 1000 do Garmin; desligou e ligou sem mudar nada.
        #expect(catchUp(1000, lastRead: GarminRead(dayKey: today, ml: 1000)) == nil)
    }

    @Test func switchingOnAgainSendsOnlyWhatChangedWhileOff() {
        let read = GarminRead(dayKey: today, ml: 1000)
        #expect(catchUp(1500, lastRead: read)?.ml == 500)
        // Um "−1" com o interruptor desligado vira registro negativo.
        #expect(catchUp(500, lastRead: read)?.ml == -500)
    }

    @Test func entryStillQueuedIsNotSentTwice() {
        // Ligou, o envio falhou (sem rede), desligou e ligou de novo.
        let queued = [item("seed", 1000, "2026-11-05T15:00:00")]
        #expect(catchUp(1000, queue: queued) == nil)
    }

    @Test func readFromAnotherDayDoesNotCount() {
        // Leitura de ontem e garrafa do Atalho de ontem na fila: só hoje entra na conta.
        let queue = [item("y", 500, "2026-11-04T22:00:00")]
        #expect(catchUp(1000, lastRead: GarminRead(dayKey: "2026-11-04", ml: 2000), queue: queue)?.ml == 1000)
    }
}

@Suite("Respostas e erros do ajudante")
struct GarminReplyTests {
    @Test func getOkReadsML() {
        let out = #"{"ok":true,"date":"2026-11-05","ml":1250,"goal_ml":2839,"last_entry_local":null}"# + "\n"
        #expect(GarminReply.parse(out) == .ok(ml: 1250))
    }

    @Test func addOkReadsTotal() {
        let out = #"{"ok":true,"date":"2026-11-05","added_ml":50,"timestamp_local":"2026-11-05T14:48:55.000","total_ml":50}"#
        #expect(GarminReply.parse(out) == .ok(ml: 50))
    }

    @Test func usesLastNonEmptyLine() {
        let out = "aviso solto\n" + #"{"ok":true,"ml":0}"# + "\n\n"
        #expect(GarminReply.parse(out) == .ok(ml: 0))
    }

    @Test func unreadableOutputIsHelperFailure() {
        #expect(GarminReply.parse("") == .failed(.helperFailed))
        #expect(GarminReply.parse("Segmentation fault") == .failed(.helperFailed))
    }

    @Test(arguments: [
        ("auth_required", GarminProblem.sessionMissing),
        ("network", .offline),
        ("rate_limited", .rateLimited),
        ("garmin_unavailable", .garminDown),
        ("garmin_changed", .helperOutdated),
        ("usage", .helperFailed),
        ("internal", .helperFailed),
        ("algo_novo", .helperFailed),
    ])
    func codeDecidesTheProblem(code: String, expected: GarminProblem) {
        let out = #"{"ok":false,"error":{"code":"\#(code)","message":"qualquer texto"}}"#
        #expect(GarminReply.parse(out) == .failed(expected))
    }

    @Test func messageIsIgnored() {
        // A mesma message com code diferente dá linhas diferentes.
        let a = #"{"ok":false,"error":{"code":"network","message":"Sessão expirada"}}"#
        #expect(GarminReply.parse(a) == .failed(.offline))
    }

    @Test func eachProblemHasItsLine() {
        #expect(GarminProblem.sessionMissing.message.contains("login no Terminal"))
        for p in [GarminProblem.offline, .rateLimited, .garminDown, .helperFailed] {
            #expect(p.message.contains("Tento de novo mais tarde"))
        }
        #expect(GarminProblem.helperOutdated.message.contains("precisa de atualização"))
        #expect(GarminProblem.nodeMissing.message.contains("brew install node"))
        #expect(GarminProblem.helperMissing.message.contains("./build.sh"))
    }

    @Test func retryLaterProblemsWaitForTheSchedule() {
        let now = at(5, 10)
        for p in [GarminProblem.offline, .rateLimited, .garminDown, .helperOutdated, .helperFailed] {
            #expect(GarminSync.retryAfter(p, now: now) == now.addingTimeInterval(15 * 60))
        }
        for p in [GarminProblem.sessionMissing, .nodeMissing, .helperMissing] {
            #expect(GarminSync.retryAfter(p, now: now) == nil)
        }
    }
}

@Suite("Quando sincronizar")
struct GarminScheduleTests {
    let now = at(5, 10)

    @Test func switchedOffNeverRuns() {
        for t in [GarminTrigger.scheduled, .switchedOn, .panelOpened, .bottle] {
            #expect(!GarminSync.shouldRun(t, enabled: false, now: now, retryAfter: nil, lastSuccess: nil, queueIsEmpty: true))
        }
    }

    @Test func afterRateLimitOnlyTheScheduleRetries() {
        let wait = now.addingTimeInterval(600)
        #expect(!GarminSync.shouldRun(.bottle, enabled: true, now: now, retryAfter: wait, lastSuccess: nil, queueIsEmpty: false))
        #expect(!GarminSync.shouldRun(.panelOpened, enabled: true, now: now, retryAfter: wait, lastSuccess: nil, queueIsEmpty: false))
        #expect(GarminSync.shouldRun(.scheduled, enabled: true, now: now, retryAfter: wait, lastSuccess: nil, queueIsEmpty: false))
        // Passada a espera, a garrafa volta a sincronizar.
        #expect(GarminSync.shouldRun(.bottle, enabled: true, now: wait, retryAfter: wait, lastSuccess: nil, queueIsEmpty: false))
    }

    @Test func reopeningThePanelRightAwayDoesNotReadAgain() {
        let justNow = now.addingTimeInterval(-20)
        #expect(!GarminSync.shouldRun(.panelOpened, enabled: true, now: now, retryAfter: nil, lastSuccess: justNow, queueIsEmpty: true))
        #expect(GarminSync.shouldRun(.panelOpened, enabled: true, now: now, retryAfter: nil, lastSuccess: justNow, queueIsEmpty: false))
        #expect(GarminSync.shouldRun(.bottle, enabled: true, now: now, retryAfter: nil, lastSuccess: justNow, queueIsEmpty: true))
        let longAgo = now.addingTimeInterval(-120)
        #expect(GarminSync.shouldRun(.panelOpened, enabled: true, now: now, retryAfter: nil, lastSuccess: longAgo, queueIsEmpty: true))
    }
}

@Suite("Garmin no estado salvo")
struct GarminPersistenceTests {
    @Test func oldStateOpensSwitchedOffWithEmptyQueue() throws {
        let old = #"{"settings":{"bottleML":500,"goalBottles":4,"intervalMin":60,"startHour":8,"endHour":22},"mlByDay":{"2026-11-05":1000},"metGoal":{},"importedFiles":[]}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(old.utf8))
        #expect(state.settings.garminEnabled == false)
        #expect(state.garminQueue.isEmpty)
        #expect(state.garminLastRead == nil)
        #expect(state.mlByDay == ["2026-11-05": 1000])
    }

    @Test func brokenQueueDoesNotWipeHistory() throws {
        let json = #"{"mlByDay":{"2026-11-05":1000},"garminQueue":"oops"}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        #expect(state.garminQueue.isEmpty)
        #expect(state.mlByDay == ["2026-11-05": 1000])
    }

    @Test func queueAndSwitchSurviveRestart() throws {
        var state = PersistedState()
        state.settings.garminEnabled = true
        state.garminQueue = [item("a", 500, "2026-11-05T08:00:00"), item("b", -500, "2026-11-05T09:00:00")]
        state.garminLastRead = GarminRead(dayKey: "2026-11-05", ml: 1500)
        let reopened = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        #expect(reopened == state)
    }
}
