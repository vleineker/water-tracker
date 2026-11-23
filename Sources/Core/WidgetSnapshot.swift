import Foundation

/// Retrato do dia que o app grava para o widget de desktop ler.
///
/// O widget roda isolado (sandbox) e não enxerga as preferências do app, então os
/// dois conversam por arquivos numa pasta só deles: o app grava `today.json` com
/// este retrato, e cada clique no "+" do widget grava um arquivo em `inbox/`, que
/// o app soma e apaga. É puro (só Foundation) e compila nos dois lados.
struct WidgetSnapshot: Codable, Equatable {
    var dayKey: String
    var todayML: Int
    var bottleML: Int
    var goalBottles: Int

    var goalML: Int { goalBottles * bottleML }

    var bottles: Int { bottleML > 0 ? todayML / bottleML : 0 }

    /// De 0 a 1, travado em 1 quando passa da meta.
    var progress: Double {
        goalML > 0 ? min(1.0, Double(todayML) / Double(goalML)) : 0
    }

    /// O retrato valendo para `todayKey`: se foi gravado em outro dia, hoje começa do zero.
    func current(todayKey: String) -> WidgetSnapshot {
        guard dayKey != todayKey else { return self }
        return WidgetSnapshot(dayKey: todayKey, todayML: 0, bottleML: bottleML, goalBottles: goalBottles)
    }

    /// Depois de um clique no "+": o widget já mostra a garrafa sem esperar o app.
    func addingBottle() -> WidgetSnapshot {
        var next = self
        next.todayML += bottleML
        return next
    }

    // MARK: - Arquivos

    /// Nome do arquivo de um clique no "+": o dia na frente, para o app não somar
    /// hoje um clique que ficou parado de ontem.
    static func tapFileName(dayKey: String, id: String) -> String { "\(dayKey)_\(id)" }

    /// Dia de um arquivo de clique, ou `nil` se o nome não segue o formato.
    static func tapDay(fromFileName name: String) -> String? {
        let parts = name.split(separator: "_", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 10 else { return nil }
        return String(parts[0])
    }

    /// Pasta de troca. Sai da conta do usuário e não de `NSHomeDirectory()`, que
    /// dentro do widget aponta para o contêiner do sandbox.
    static var folder: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Gota/widget", isDirectory: true)
    }

    static var file: URL { folder.appendingPathComponent("today.json") }
    static var inbox: URL { folder.appendingPathComponent("inbox", isDirectory: true) }

    static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func write() {
        try? FileManager.default.createDirectory(at: Self.inbox, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.file, options: .atomic)
    }
}
