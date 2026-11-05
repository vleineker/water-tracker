# Gota

Lembrete e tracker de água na barra de menus do macOS. Registre cada
garrafa pelo Mac, por um Atalho do iPhone ou, se quiser, pelo relógio
Garmin, e tudo cai no mesmo dia.

App nativo em Swift/SwiftUI (`MenuBarExtra`), sem Dock, para macOS 14
ou superior. O app em Swift não tem dependências e compila direto com
`swiftc`, sem Xcode. Só o Garmin, que é opcional, usa um ajudante em
Node.

## Uso

- A gota na barra de menus enche de baixo para cima conforme o dia
  avança rumo à meta. Ela segue o tema do macOS (preta no claro,
  branca no escuro).
- Clique na gota para abrir o painel: quantas garrafas foram hoje,
  botões "+1 garrafa" e "−1" (pede confirmação antes de remover), a
  sequência de dias com meta batida, os últimos 7 dias e os
  **Ajustes**: tamanho da garrafa, meta, espaço mínimo entre
  lembretes, início e fim do dia, "Abrir ao iniciar sessão", Garmin e
  "Testar lembrete".
- Quando sai uma versão nova no GitHub, o painel mostra "Nova versão
  disponível".
- "Sair" (⌘Q) no rodapé do painel encerra o app.

### Lembrete só quando atrasado

O Gota não lembra de hora em hora. Ele divide a meta pelo dia ativo
(entre o início e o fim dos Ajustes) e só avisa quando o que você
bebeu fica atrás desse ritmo. Exemplo com meta de 4 garrafas das 8h
às 22h: com nada bebido, o aviso vem às 8h; com 2 garrafas, só às
15h. O "Espaço mínimo" é o tempo mínimo entre um aviso e o seguinte
(ou entre a última garrafa e o próximo aviso). Fora do dia ativo, ou
com a meta batida, nada toca. O aviso é agendado no próprio macOS,
então chega mesmo com o Mac dormindo e acordando.

### Notificações

Na primeira execução, o macOS pede permissão: clique em "Permitir"
para receber os lembretes. Recomendado: em **Ajustes do Sistema >
Notificações > Gota**, trocar o estilo de **Banners** para
**Alertas**. No estilo Banners, as ações ("Bebi uma garrafa" e
"Lembrar em 15 min") ficam escondidas sob "Opções". Com as
notificações negadas, o painel mostra um sino cortado ao lado do
nome.

### Registrar pelo iPhone (Atalho)

Longe do Mac, um Atalho do iPhone registra a garrafa gravando um arquivo
no iCloud Drive. O Mac soma esse arquivo ao dia em que ele foi criado
(não ao dia em que o Mac leu) e depois apaga o arquivo. Não precisa de
app no iPhone nem do Garmin.

**Como funciona:** cada garrafa é um arquivo na pasta
`iCloud Drive/Gota/inbox`, com o horário no nome, no formato
`2026-11-05T14-32-00.txt`. O conteúdo do arquivo não importa. O Mac lê
a pasta ao abrir o painel, ao acordar e a cada 15 minutos, e soma uma
garrafa do tamanho configurado nos Ajustes por arquivo. Arquivo com
nome fora do formato é ignorado e fica na pasta. A pasta é criada pelo
próprio Gota na primeira leitura; se ela ainda não aparecer no iPhone,
crie `Gota/inbox` no app Arquivos, dentro do iCloud Drive.

**Montando o Atalho** (app Atalhos no iPhone, "+" para criar):

1. Ação **Data Atual**.
2. Ação **Formatar Data**: Formato de Data **Personalizado**, com o
   formato `yyyy-MM-dd'T'HH-mm-ss` (as aspas simples em volta do `T`
   fazem parte).
3. Ação **Texto**, com qualquer conteúdo (por exemplo, `1`).
4. Ação **Definir Nome**: nome = **Data Formatada** (a variável da
   etapa 2). Com ou sem `.txt` no fim, o Gota aceita.
5. Ação **Salvar Arquivo**: desligue **Perguntar Onde Salvar**, escolha
   a pasta **iCloud Drive › Gota › inbox** e deixe **Substituir Se o
   Arquivo Existir** desligado (dois toques no mesmo segundo viram
   duas garrafas).
6. Dê um nome curto ao Atalho, como "Bebi uma garrafa", e adicione à
   Tela de Início, ao botão de Ação ou ao Apple Watch.

Para conferir: rode o Atalho, abra o painel do Gota no Mac (com o
iCloud já sincronizado) e veja a garrafa somada; o arquivo some da
pasta. O macOS pode pedir permissão para o Gota acessar o iCloud
Drive na primeira leitura. Se a permissão for negada, o app segue
funcionando, só sem as garrafas do iPhone.

### Garmin (opcional)

Desligado de fábrica. Ligado o interruptor **Garmin** nos Ajustes,
cada garrafa do Mac ou do iPhone vai para o Garmin Connect, e o total
de hoje passa a ser o do Garmin. Assim, o que você registra no
relógio também entra no dia do Gota. Sem internet, as garrafas ficam
numa fila e vão quando a conexão voltar.

Precisa de:

- **Node 20 ou mais novo**, instalado pelo Homebrew (`brew install
  node`). O app procura em `/opt/homebrew/bin/node` e
  `/usr/local/bin/node`.
- **Login no Garmin, uma vez, pelo Terminal.** Com o interruptor
  ligado e sem sessão, o painel mostra o comando e um botão "Copiar
  comando". Cole no Terminal e digite e-mail, senha e, se pedir, o
  código de duas etapas. A senha não é gravada; só a sessão fica em
  `~/Library/Application Support/Gota/garmin/`. Para sair, apague essa
  pasta.

No relógio, o resumo de hidratação depende do modelo. No Forerunner
265 ele vem do app gratuito **Hydration**, da loja Connect IQ,
instalado à parte pelo app Connect IQ do celular. É nele
que aparecem as garrafas vindas do Gota e que se registra água pelo
relógio.

A Garmin não tem API oficial para água. O ajudante usa um cliente
não oficial e pode quebrar quando a Garmin mudar algo; nesse caso o
painel avisa, e o resto do app segue funcionando. Detalhes do
ajudante em [`garmin/README.md`](garmin/README.md).

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

Testa as regras puras de `Sources/Core/` (progresso e meta, ritmo do
lembrete, gota da barra, Atalho do iPhone, fila do Garmin, estado
salvo, login item) com swift-testing. O `swift test` não funciona com
o Command Line Tools sem Xcode (o SwiftPM não consegue ler o
`Package.swift`), então o `test.sh` compila os testes direto com
`swiftc` num executável em `build/GotaTests`. O `build.sh` roda os
testes antes de compilar o app e para se algum falhar. O ajudante do
Garmin tem testes próprios: `cd garmin && npm test`.

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

## Debug do lembrete

"Testar lembrete", nos Ajustes, mostra um aviso na hora. Para ver o
ritmo funcionando sem esperar o "Espaço mínimo" real:

```bash
defaults write com.vleineker.gota gota.debugIntervalSeconds 60
```

O valor, em segundos, substitui o "Espaço mínimo" no cálculo do
próximo lembrete; o dia ativo (início e fim) continua valendo e o
aviso só toca com o dia atrasado. Reabra o app para valer. Para
voltar ao normal:

```bash
defaults delete com.vleineker.gota gota.debugIntervalSeconds
```

## Dados

Ajustes e histórico ficam em `UserDefaults`, na chave
`gota.state.v2`, em ml por dia (`defaults read com.vleineker.gota
gota.state.v2`). O histórico guarda os últimos 30 dias. Quem vinha da
versão 1.1 tem o formato antigo (`gota.state.v1`, garrafas por dia)
convertido uma vez, na primeira abertura.

## Login item

Ligado por padrão na primeira execução (`SMAppService.mainApp`,
guardado por `gota.didRegisterLoginItem`, então não religa sozinho se
você desligar depois). Pode exigir aprovação em **Ajustes do Sistema
> Geral > Itens de Início**; o painel mostra um botão "Aprovar nos
Ajustes" quando necessário.

Se o registro pelo sistema falhar, o Gota grava um LaunchAgent de
reserva em `~/Library/LaunchAgents/com.vleineker.gota.plist`.
Desligar "Abrir ao iniciar sessão" apaga esse arquivo, se ele
existir.

## Contribuir e licença

Como compilar, testar e mandar mudanças: [`CONTRIBUTING.md`](CONTRIBUTING.md).
Código sob a licença MIT ([`LICENSE`](LICENSE)).
