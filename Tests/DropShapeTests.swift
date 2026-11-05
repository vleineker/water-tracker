import Foundation
import Testing

@Suite("Gota da barra")
struct DropShapeTests {
    @Test func emptyAndFullAreTheEnds() {
        #expect(DropShape.fillLevel(progress: 0) == 0)
        #expect(DropShape.fillLevel(progress: 1) == 1)
    }

    @Test func outOfRangeProgressIsClamped() {
        #expect(DropShape.fillLevel(progress: -0.5) == 0)
        #expect(DropShape.fillLevel(progress: 1.7) == 1)
    }

    @Test func levelGrowsWithProgress() {
        let levels = [0.0, 0.25, 0.5, 0.75, 1.0].map { DropShape.fillLevel(progress: $0) }
        #expect(levels == levels.sorted())
        #expect(Set(levels).count == levels.count)
    }

    /// A gota é mais larga embaixo: metade da área fica abaixo da metade da altura.
    @Test func halfTheAreaSitsBelowHalfTheHeight() {
        let level = DropShape.fillLevel(progress: 0.5)
        #expect(level > 0.3 && level < 0.5)
    }

    @Test func widestPointIsTheCircleCenter() {
        #expect(abs(DropShape.halfWidth(atY: DropShape.center.y) - DropShape.radius) < 0.01)
        #expect(DropShape.halfWidth(atY: DropShape.top) == 0)
        #expect(DropShape.halfWidth(atY: DropShape.bottom) == 0)
    }
}

@Suite("Ajustes salvos")
struct SettingsDecodeTests {
    /// Dado salvo antes da issue #3 ainda tem `showCountInBar`; o decode ignora o campo.
    @Test func oldDataWithShowCountInBarStillDecodes() throws {
        let json = """
        {"bottleML":750,"goalBottles":3,"intervalMin":45,"startHour":9,"endHour":21,"showCountInBar":false}
        """
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.bottleML == 750)
        #expect(settings.goalBottles == 3)
        #expect(settings.endHour == 21)
    }
}
