import Foundation
import Testing

@Suite("Retrato do widget")
struct WidgetSnapshotTests {
    let half = WidgetSnapshot(dayKey: "2026-11-22", todayML: 1000, bottleML: 500, goalBottles: 4)

    @Test func progressAndBottlesComeFromML() {
        #expect(half.progress == 0.5)
        #expect(half.bottles == 2)
        #expect(half.goalML == 2000)
    }

    @Test func progressStopsAtTheGoal() {
        var over = half
        over.todayML = 5000
        #expect(over.progress == 1)
    }

    @Test func zeroGoalIsZeroProgress() {
        #expect(WidgetSnapshot(dayKey: "x", todayML: 500, bottleML: 0, goalBottles: 4).progress == 0)
    }

    @Test func sameDayKeepsTheTotal() {
        #expect(half.current(todayKey: "2026-11-22") == half)
    }

    @Test func anotherDayStartsFromZeroWithTheSameSettings() {
        let next = half.current(todayKey: "2026-11-23")
        #expect(next == WidgetSnapshot(dayKey: "2026-11-23", todayML: 0, bottleML: 500, goalBottles: 4))
    }

    @Test func addingBottleAddsOneBottleOfML() {
        #expect(half.addingBottle().todayML == 1500)
    }

    @Test func tapFileNameCarriesTheDay() {
        let name = WidgetSnapshot.tapFileName(dayKey: "2026-11-22", id: "ABC_1")
        #expect(WidgetSnapshot.tapDay(fromFileName: name) == "2026-11-22")
        #expect(WidgetSnapshot.tapDay(fromFileName: ".DS_Store") == nil)
        #expect(WidgetSnapshot.tapDay(fromFileName: "today.json") == nil)
    }
}
