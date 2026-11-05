# Gota

Lembrete e tracker de água na barra de menus do macOS. App nativo em
Swift/SwiftUI (`MenuBarExtra`), sem Dock, sem dependências externas —
compilado direto com `swiftc` (sem Xcode).

## Uso

- Ícone na barra mostra o estágio da gota (`drop` / `drop.halffull` /
  `drop.fill`) e, opcionalmente, "n/meta".
- Clique no ícone abre o painel: anel de progresso, botões "+1
  garrafa" / "−1", status do próximo lembrete, faixa dos últimos 7
  dias e "Ajustes" (garrafa, meta, intervalo, janela ativa, login
  item, exibir contagem na barra, "Testar lembrete").
- "Sair" (⌘Q) no rodapé do painel encerra o app.

### Notificações

Na primeira execução, o macOS pede permissão — clique em "Permitir"
para receber os lembretes. Recomendado: em **Ajustes do Sistema >
Notificações > Gota**, trocar o estilo de **Banners** para
**Alertas** — no estilo Banners, as ações ("Bebi uma garrafa" /
"Lembrar em 15 min") ficam escondidas sob "Opções".

## Instalar

### Pelo código (recomendado se você usa terminal)

```bash
xcode-select --install
git clone https://github.com/vleineker/water-tracker.git
cd water-tracker && ./build.sh
```

Compila localmente, binário universal (Apple Silicon e Intel), macOS
14 ou superior, sem precisar de Xcode.

### Pelo zip (Releases)

1. Baixe `Gota-x.y.z.zip` na página de Releases do repositório.
2. Descompacte e mova `Gota.app` para `~/Applications` (ou
   `/Applications`).
3. Abra o app.

O macOS vai avisar que o app não foi verificado (assinatura ad-hoc,
sem Developer ID) — não há conta de desenvolvedor Apple por trás,
mas o código é aberto e dá para compilar você mesmo.

- **macOS 15 ou superior**: após o primeiro clique bloqueado, vá em
  **Ajustes do Sistema > Privacidade e Segurança**, role até o aviso
  sobre o Gota e clique **Abrir Mesmo Assim** — só precisa uma vez.
- **macOS 14**: botão direito no app > **Abrir** > **Abrir**.
- **Alternativa via terminal**, sem passar pelo aviso:

  ```bash
  xattr -d com.apple.quarantine ~/Applications/Gota.app
  ```

Na primeira abertura o app pede permissão de notificações e se
registra como item de início — ver as seções "Notificações" e
"Login item" mais abaixo.

## Build

```bash
./build.sh
```

Compila via `swiftc` (SDK do Command Line Tools, sem Xcode), monta
`build/Gota.app`, assina ad-hoc, mata qualquer instância em execução,
instala em `~/Applications/Gota.app` e abre. `build/` é removido ao
final — a cópia instalada é a única fonte de verdade.

Rebuildar após qualquer mudança em `Sources/` ou
`Resources/Info.plist`: basta rodar `./build.sh` de novo.

### Testes

```bash
./test.sh
```

Testa as regras de hidratação (`Sources/Core/HydrationLog.swift`: progresso,
meta batida, streak, últimos 7 dias, validação de início/fim) com
swift-testing. O `swift test` não funciona com o Command Line Tools desta
máquina (o SwiftPM não consegue ler nenhum `Package.swift`), então o
`test.sh` compila os testes direto com `swiftc` num executável em
`build/GotaTests`. O `build.sh` roda os testes antes de compilar o app e para
se algum falhar.

### Rebuild automático (opcional, local)

```bash
git config core.hooksPath hooks
```

Ativa os hooks de `hooks/`: após `commit` ou `merge`/`pull` em `main`
que mude `Sources/`, `Resources/` ou `build.sh`, o `./build.sh` roda
em background (não trava o git). Log em `.git/hook-build.log`. Para
desativar: `git config --unset core.hooksPath`.

## Desinstalar

```bash
./uninstall.sh
```

Desregistra o login item, remove o LaunchAgent de fallback (se
existir), mata o processo, remove `~/Applications/Gota.app` e limpa
as preferências (`defaults delete com.vleineker.gota`).

## Debug do lembrete (sem esperar o intervalo real)

Por padrão o intervalo de lembrete é configurável nos Ajustes (15–240
min). Para testar o scheduler sem esperar:

```bash
pkill -x Gota
defaults write com.vleineker.gota gota.debugIntervalSeconds 60
open ~/Applications/Gota.app
# espera ~90s (heartbeat de 30s + tolerância) e observa o lembrete
defaults delete com.vleineker.gota gota.debugIntervalSeconds
```

O override é lido em segundos e substitui o intervalo configurado
(`intervalMin`) só para o cálculo do próximo lembrete — a janela
ativa (início/fim) continua valendo.

## Dados

Estado (ajustes + histórico diário) persiste em `UserDefaults` sob a
chave `gota.state.v1` (`defaults read com.vleineker.gota
gota.state.v1`). Histórico é aparado para os últimos 30 dias.

## Login item

Ligado por padrão na primeira execução (`SMAppService.mainApp`,
guardado por `gota.didRegisterLoginItem` — não religa automaticamente
se desligado depois). Pode exigir aprovação em **Ajustes > Geral >
Itens de Início** — o painel mostra um botão "Aprovar nos Ajustes"
quando necessário.
