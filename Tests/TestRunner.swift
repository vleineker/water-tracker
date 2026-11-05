import Testing

/// Ponto de entrada do executável de testes. O `swift test` não roda nesta máquina
/// (o SwiftPM do Command Line Tools não consegue ler nenhum `Package.swift`), então o
/// `test.sh` compila os testes com `swiftc` e este `main` chama o mesmo runner do
/// swift-testing que o `swift test` usaria. Sai com código diferente de 0 se algum falhar.
@main
struct TestRunner {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
