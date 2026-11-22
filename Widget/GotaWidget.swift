import WidgetKit
import SwiftUI
import AppIntents

/// Widget de desktop do Gota: o cartão é um tanque que enche conforme o dia avança
/// rumo à meta, com um "+" que registra uma garrafa. Os dados vêm do arquivo que o
/// app grava (ver `WidgetSnapshot`); o widget nunca lê as preferências do app.

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .current
    return c
}()

private func dayKey(_ date: Date) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

private func snapshot(at date: Date) -> WidgetSnapshot {
    let saved = WidgetSnapshot.read()
        ?? WidgetSnapshot(dayKey: dayKey(date), todayML: 0, bottleML: 500, goalBottles: 4)
    return saved.current(todayKey: dayKey(date))
}

struct AddBottleIntent: AppIntent {
    static var title: LocalizedStringResource = "Bebi uma garrafa"

    /// Deixa um arquivo para o app somar e já atualiza o retrato, para o tanque
    /// subir na hora mesmo se o app demorar a responder.
    func perform() async throws -> some IntentResult {
        let now = snapshot(at: Date())
        try? FileManager.default.createDirectory(at: WidgetSnapshot.inbox, withIntermediateDirectories: true)
        let tap = WidgetSnapshot.inbox.appendingPathComponent(
            WidgetSnapshot.tapFileName(dayKey: now.dayKey, id: UUID().uuidString))
        try Data().write(to: tap)
        now.addingBottle().write()
        return .result()
    }
}

struct TankEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TankProvider: TimelineProvider {
    func placeholder(in context: Context) -> TankEntry {
        TankEntry(date: Date(), snapshot: WidgetSnapshot(dayKey: "", todayML: 1000, bottleML: 500, goalBottles: 4))
    }

    func getSnapshot(in context: Context, completion: @escaping (TankEntry) -> Void) {
        completion(TankEntry(date: Date(), snapshot: snapshot(at: Date())))
    }

    /// Agora e a virada do dia, quando o tanque esvazia sozinho.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TankEntry>) -> Void) {
        let now = Date()
        var entries = [TankEntry(date: now, snapshot: snapshot(at: now))]
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(TankEntry(date: midnight, snapshot: snapshot(at: midnight)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Água até `level` (0 = vazio, 1 = cheio), com a superfície em onda.
struct Water: Shape {
    var level: Double
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let amplitude = level <= 0 || level >= 1 ? 0 : rect.height * 0.03
        let surface = rect.maxY - rect.height * level
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for x in stride(from: rect.minX, through: rect.maxX, by: 2) {
            let angle = (x - rect.minX) / rect.width * 4 * .pi + phase
            path.addLine(to: CGPoint(x: x, y: surface + sin(angle) * amplitude))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct TankView: View {
    let snapshot: WidgetSnapshot

    private static let blue = Color(nsColor: .systemBlue)

    private var liters: String {
        (Double(snapshot.todayML) / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR"))) + " L"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int((snapshot.progress * 100).rounded()))%")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(snapshot.bottles) de \(snapshot.goalBottles) garrafas")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(liters)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Button(intent: AddBottleIntent()) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Self.blue)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .containerBackground(for: .widget) {
            ZStack {
                Color(red: 0.11, green: 0.11, blue: 0.12)
                Water(level: snapshot.progress, phase: .pi).fill(Self.blue.opacity(0.55))
                Water(level: snapshot.progress, phase: 0).fill(Self.blue)
            }
        }
    }
}

@main
struct GotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.vleineker.gota.tank", provider: TankProvider()) { entry in
            TankView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Gota")
        .description("Quanto você já bebeu hoje, com um toque para registrar uma garrafa.")
        .supportedFamilies([.systemSmall])
    }
}
