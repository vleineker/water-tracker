import Foundation
import Observation

/// Roda o ajudante `gota-garmin.mjs` (dentro do `.app`, em `Resources/garmin`) com o
/// `node` do Homebrew. Uma execução por vez, fora da thread principal.
enum GarminHelper {
    static let nodeCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
    /// O ajudante já para sozinho em 45 s; isto só cobre um `node` travado.
    static let processTimeout: TimeInterval = 75

    static var nodePath: String? {
        nodeCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var scriptPath: String? {
        Bundle.main.url(forResource: "gota-garmin", withExtension: "mjs", subdirectory: "garmin")?.path
    }

    /// Comando para colar no Terminal quando falta a sessão do Garmin.
    static var loginCommand: String {
        let node = nodePath ?? nodeCandidates[0]
        let script = scriptPath ?? "~/Applications/Gota.app/Contents/Resources/garmin/gota-garmin.mjs"
        return "'\(node)' '\(script)' login"
    }

    /// Executa `get`/`add` e devolve a resposta lida do JSON. Nunca lança: sem `node`,
    /// sem o ajudante ou com o processo quebrado, devolve o erro correspondente.
    static func run(_ arguments: [String]) -> GarminReply {
        guard let node = nodePath else { return .failed(.nodeMissing) }
        guard let script = scriptPath else { return .failed(.helperMissing) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [script] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: script).deletingLastPathComponent()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            NSLog("Gota: não deu para rodar o ajudante do Garmin: \(error.localizedDescription)")
            return .failed(.helperFailed)
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + processTimeout, execute: watchdog)

        // Lê as duas saídas em paralelo para nenhuma encher o buffer e travar o processo.
        var errData = Data()
        let errRead = DispatchGroup()
        errRead.enter()
        DispatchQueue.global().async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            errRead.leave()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        errRead.wait()
        process.waitUntilExit()
        watchdog.cancel()

        let reply = GarminReply.parse(String(decoding: outData, as: UTF8.self))
        if case .failed(let problem) = reply {
            let tail = String(decoding: errData.suffix(500), as: UTF8.self)
            NSLog("Gota: ajudante do Garmin (\(arguments.first ?? "")) falhou: \(problem); stderr: \(tail)")
        }
        return reply
    }
}

/// Sincroniza a fila e o total de hoje com o Garmin Connect. As regras (quando rodar,
/// o que sai da fila, o total) moram em `GarminSync`, no núcleo.
///
/// Com o interruptor desligado, nada aqui chama o ajudante.
@MainActor
@Observable
final class GarminSyncer {
    static let shared = GarminSyncer()

    /// Último erro, para a linha discreta do painel. `nil` depois de um sucesso.
    private(set) var problem: GarminProblem?

    @ObservationIgnored private var running = false
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var retryAfter: Date?
    @ObservationIgnored private var lastSuccess: Date?
    @ObservationIgnored private var timer: Timer?

    private init() {}

    private var store: HydrationStore { HydrationStore.shared }

    /// Liga o relógio de 15 min e sincroniza uma vez (se o interruptor estiver ligado).
    func start() {
        if timer == nil {
            let timer = Timer(timeInterval: GarminSync.interval, repeats: true) { _ in
                Task { @MainActor in GarminSyncer.shared.sync(.scheduled) }
            }
            timer.tolerance = 60
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        sync(.scheduled)
    }

    /// Chamado ao desligar o interruptor: some a linha do painel e a espera.
    func reset() {
        problem = nil
        retryAfter = nil
        lastSuccess = nil
    }

    func sync(_ trigger: GarminTrigger) {
        guard store.settings.garminEnabled else { return }
        if running {
            // Uma garrafa durante a sincronização: roda de novo no fim, uma vez só.
            if trigger == .bottle { rerunRequested = true }
            return
        }
        guard GarminSync.shouldRun(
            trigger, enabled: true, now: Date(),
            retryAfter: retryAfter, lastSuccess: lastSuccess, queueIsEmpty: store.garminQueue.isEmpty
        ) else { return }

        running = true
        Task {
            await runOnce()
            running = false
            if rerunRequested {
                rerunRequested = false
                sync(.bottle)
            }
        }
    }

    /// Envia a fila em ordem e para no primeiro erro; depois lê o total de hoje.
    private func runOnce() async {
        for item in store.garminQueue {
            guard store.settings.garminEnabled else { return }
            let args = ["add", String(item.ml), item.localTime]
            let reply = await Task.detached { GarminHelper.run(args) }.value
            store.garminSent(item.id, reply: reply)
            if case .failed(let p) = reply { return fail(p) }
        }
        guard store.settings.garminEnabled else { return }
        let dayKey = store.todayKey
        let reply = await Task.detached { GarminHelper.run(["get", dayKey]) }.value
        switch reply {
        case .failed(let p):
            fail(p)
        case .ok(let ml):
            guard store.settings.garminEnabled else { return }
            store.applyGarminToday(ml ?? 0, dayKey: dayKey)
            problem = nil
            retryAfter = nil
            lastSuccess = Date()
        }
    }

    private func fail(_ p: GarminProblem) {
        guard store.settings.garminEnabled else { return }
        problem = p
        retryAfter = GarminSync.retryAfter(p, now: Date())
    }
}
