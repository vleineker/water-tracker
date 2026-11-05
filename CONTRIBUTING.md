# Contribuindo com o Gota

Obrigado pelo interesse. O Gota é pequeno de propósito: um app de barra de
menus que faz uma coisa. Mudança boa é a que deixa o app mais simples ou mais
confiável; feature nova vale conversar numa issue antes.

## Preparar a máquina

Precisa de macOS 14 ou superior e do Command Line Tools. Não precisa de Xcode.

```bash
xcode-select --install
git clone https://github.com/vleineker/water-tracker.git
cd water-tracker
```

Para mexer no Garmin, também precisa de Node 20 ou mais novo
(`brew install node`).

## Compilar e testar

```bash
./test.sh    # só os testes
./build.sh   # testes, compila, instala em ~/Applications/Gota.app e abre
```

O `build.sh` para se algum teste falhar. O ajudante do Garmin tem testes
próprios, que nunca falam com a Garmin de verdade:

```bash
cd garmin && npm ci && npm test
```

## Como o código está organizado

- `Sources/Core/`: as regras do app, puras e sem AppKit nem SwiftUI (progresso,
  ritmo do lembrete, gota da barra, Atalho do iPhone, fila do Garmin, estado
  salvo, login item). Toda regra nova entra aqui, com teste em `Tests/`.
- `Sources/`: a parte que fala com o sistema (painel, barra de menus,
  notificações, arquivos, login item, ajudante do Garmin).
- `garmin/`: o ajudante em Node que lê e grava a água no Garmin Connect. O
  contrato com o app está em `garmin/README.md`.

## Cuidados do setup sem Xcode

- Nada de dependência nova no app Swift.
- `@State` não compila com o Command Line Tools sozinho. Use uma classe
  `@Observable` com `@Bindable`, como `LoginItemUIState` e `PanelUIState`.
- A interface é em português do Brasil.

## Mandando uma mudança

1. Abra uma issue descrevendo o problema ou a ideia, se ainda não houver.
2. Crie uma branch a partir da `main`.
3. Commits em inglês, no formato conventional commits (`feat:`, `fix:`,
   `docs:`, `chore:`).
4. Rode `./build.sh` e use o app de verdade antes de abrir o pull request.
5. No pull request, diga o que mudou para quem usa e como você testou.
6. Nunca suba tokens, sessões do Garmin ou dados pessoais. Os arquivos de sessão
   já estão no `.gitignore`.

Ao contribuir, você concorda em licenciar sua contribuição sob a licença MIT
do projeto (`LICENSE`).
