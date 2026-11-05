import Foundation
import Testing

/// Meta padrão: 4 garrafas de 500 ml (2 L).
private func state(
    mlByDay: [String: Int] = [:],
    metGoal: [String: Bool] = [:],
    importedFiles: [String] = [],
    settings: Settings = Settings()
) -> PersistedState {
    PersistedState(settings: settings, mlByDay: mlByDay, metGoal: metGoal, importedFiles: importedFiles)
}

@Suite("Atalho do iPhone: nome do arquivo")
struct PhoneInboxFileNameTests {
    @Test func readsDayAndTimeFromName() {
        #expect(PhoneInbox.stamp(fromFileName: "2026-11-05T14-32-00.txt")
            == PhoneInbox.Stamp(dayKey: "2026-11-05", hour: 14, minute: 32, second: 0))
    }

    @Test func acceptsNoExtensionAndICloudDuplicateSuffix() {
        #expect(PhoneInbox.stamp(fromFileName: "2026-11-05T23-59-59")?.dayKey == "2026-11-05")
        #expect(PhoneInbox.stamp(fromFileName: "2026-11-05T14-32-00 2.txt")?.dayKey == "2026-11-05")
        #expect(PhoneInbox.stamp(fromFileName: "2026-11-05T14-32-00-1.txt")?.dayKey == "2026-11-05")
    }

    @Test func leapDayIsValid() {
        #expect(PhoneInbox.stamp(fromFileName: "2028-02-29T08-00-00.txt")?.dayKey == "2028-02-29")
    }

    @Test(arguments: [
        "",
        "garrafa.txt",
        ".DS_Store",
        ".2026-11-05T14-32-00.txt.icloud",
        "2026-11-05 14-32-00.txt",
        "2026-11-05T14:32:00.txt",
        "2026-11-05T14-32.txt",
        "2026-11-05T14-32-001.txt",
        "2026-13-05T14-32-00.txt",
        "2026-02-30T14-32-00.txt",
        "2027-02-29T14-32-00.txt",
        "2026-11-05T24-00-00.txt",
        "2026-11-05T14-60-00.txt",
        "2026-11-05T14-32-60.txt",
        "２０２６-11-05T14-32-00.txt",
    ])
    func malformedNameIsRejected(_ name: String) {
        #expect(PhoneInbox.stamp(fromFileName: name) == nil)
    }
}

@Suite("Atalho do iPhone: soma")
struct PhoneInboxImportTests {
    @Test func fileAddsOneBottleToTheDayInItsName() {
        let outcome = PhoneInbox.importing(
            ["2026-11-04T21-10-00.txt"],
            into: state(mlByDay: ["2026-11-04": 500, "2026-11-05": 1000])
        )
        #expect(outcome.state.mlByDay == ["2026-11-04": 1000, "2026-11-05": 1000])
        #expect(outcome.addedBottles == 1)
        #expect(outcome.filesToDelete == ["2026-11-04T21-10-00.txt"])
    }

    @Test func usesCurrentBottleSize() {
        let outcome = PhoneInbox.importing(
            ["2026-11-05T08-00-00.txt", "2026-11-05T09-00-00.txt"],
            into: state(settings: Settings(bottleML: 750))
        )
        #expect(outcome.state.mlByDay == ["2026-11-05": 1500])
        #expect(outcome.addedBottles == 2)
    }

    @Test func malformedFileIsIgnoredAndNotDeleted() {
        let outcome = PhoneInbox.importing(
            ["anotacao.txt", ".DS_Store", "2026-11-05T08-00-00.txt"],
            into: state()
        )
        #expect(outcome.state.mlByDay == ["2026-11-05": 500])
        #expect(outcome.filesToDelete == ["2026-11-05T08-00-00.txt"])
    }

    @Test func onlyMalformedFilesChangeNothing() {
        let before = state(mlByDay: ["2026-11-05": 500])
        let outcome = PhoneInbox.importing(["anotacao.txt"], into: before)
        #expect(outcome.state == before)
        #expect(outcome.filesToDelete.isEmpty)
        #expect(outcome.addedBottles == 0)
    }

    @Test func fileIsRememberedSoItNeverCountsTwice() {
        let name = "2026-11-05T08-00-00.txt"
        let first = PhoneInbox.importing([name], into: state())
        #expect(first.state.importedFiles == [name])

        // Apagar falhou e o arquivo continua na pasta na próxima leitura.
        let second = PhoneInbox.importing([name], into: first.state)
        #expect(second.state.mlByDay == ["2026-11-05": 500])
        #expect(second.addedBottles == 0)
        #expect(second.filesToDelete == [name])
    }

    @Test func iCloudDuplicateCountsAsAnotherBottle() {
        let outcome = PhoneInbox.importing(
            ["2026-11-05T08-00-00.txt", "2026-11-05T08-00-00 2.txt"],
            into: state()
        )
        #expect(outcome.state.mlByDay == ["2026-11-05": 1000])
    }

    @Test func pastDayThatReachesGoalBecomesMet() {
        let outcome = PhoneInbox.importing(
            ["2026-11-04T22-00-00.txt"],
            into: state(mlByDay: ["2026-11-04": 1500], metGoal: ["2026-11-04": false])
        )
        #expect(outcome.state.mlByDay["2026-11-04"] == 2000)
        #expect(outcome.state.metGoal["2026-11-04"] == true)
    }

    @Test func importNeverUnmarksAMetDay() {
        // Meta subiu depois do dia: o dia segue batido.
        let outcome = PhoneInbox.importing(
            ["2026-11-04T22-00-00.txt"],
            into: state(mlByDay: ["2026-11-04": 2000], metGoal: ["2026-11-04": true],
                        settings: Settings(goalBottles: 8))
        )
        #expect(outcome.state.metGoal["2026-11-04"] == true)
    }

    @Test func dayBelowGoalIsRecordedAsNotMet() {
        let outcome = PhoneInbox.importing(["2026-11-03T10-00-00.txt"], into: state())
        #expect(outcome.state.metGoal["2026-11-03"] == false)
    }

    @Test func rememberedFilesAreCapped() {
        let old = (0..<PhoneInbox.rememberedFilesLimit).map {
            String(format: "2026-10-01T00-%02d-%02d.txt", $0 / 60, $0 % 60)
        }
        let newest = "2026-11-05T08-00-00.txt"
        let outcome = PhoneInbox.importing([newest], into: state(importedFiles: old))
        #expect(outcome.state.importedFiles.count == PhoneInbox.rememberedFilesLimit)
        #expect(outcome.state.importedFiles.last == newest)
        #expect(!outcome.state.importedFiles.contains(old[0]))
    }
}

@Suite("Atalho do iPhone: estado salvo")
struct PhoneInboxPersistenceTests {
    @Test func savedStateWithoutImportedFilesStillLoads() throws {
        let json = #"{"settings":{"bottleML":500},"mlByDay":{"2026-11-05":1000},"metGoal":{}}"#
        let decoded = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        #expect(decoded.mlByDay == ["2026-11-05": 1000])
        #expect(decoded.importedFiles.isEmpty)
    }

    @Test func importedFilesSurviveSaveAndLoad() throws {
        let original = state(mlByDay: ["2026-11-05": 500], importedFiles: ["2026-11-05T08-00-00.txt"])
        let decoded = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
