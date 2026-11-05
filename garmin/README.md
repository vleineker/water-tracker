# gota-garmin

Ajudante em Node que lê e grava a hidratação do dia no Garmin Connect. O app
Swift chama este comando e lê a resposta em JSON (issue #8). Nenhuma API oficial
da Garmin cobre água, por isso usamos o cliente não oficial
`@flow-js/garmin-connect` (versão fixa em `package.json`). Se ele quebrar, dá
para trocar a biblioteca, ou reescrever em Python com `python-garminconnect`,
sem mexer no app, desde que o contrato abaixo continue igual.

## Instalação

```bash
cd garmin && npm ci
```

Precisa de Node 20 ou mais novo. Os testes (`npm test`) nunca falam com a
Garmin: rodam contra um servidor local.

## Contrato

Cada execução escreve **exatamente uma linha JSON** na saída padrão e termina
com código 0 (sucesso) ou 1 (erro). Avisos da biblioteca e perguntas do login
vão para a saída de erro.

### `login`

Interativo, só no Terminal. Pede e-mail, senha e, se a conta tiver verificação
em duas etapas, o código. A senha não é gravada; só a sessão.

```json
{"ok":true,"display_name":"fulano","mfa":true,"token_dir":"/Users/…/Gota/garmin"}
```

### `get <AAAA-MM-DD>`

Total de água do dia, em ml. Dia sem registro devolve `ml: 0`.

```json
{"ok":true,"date":"2026-11-05","ml":1250,"goal_ml":2500,"last_entry_local":"2026-11-05T13:10:00.0"}
```

### `add <ml> <horário ISO 8601>`

Soma uma quantidade ao dia do horário informado, no fuso do Mac. Aceita horário
com ou sem fuso (`2026-11-05T14:30:00` ou `2026-11-05T14:30:00-03:00`).
Quantidade negativa remove água, como a correção do app Garmin Connect.
`total_ml` é o total do dia depois da gravação.

```json
{"ok":true,"date":"2026-11-05","added_ml":500,"timestamp_local":"2026-11-05T14:30:00.000","total_ml":1750}
```

### Erros

```json
{"ok":false,"error":{"code":"auth_required","message":"Sem sessão do Garmin…"}}
```

`message` é texto para pessoas e pode mudar. `detail`, quando vem, é a mensagem
crua da biblioteca, útil para diagnóstico. Quem decide o que fazer é o `code`,
que é estável:

- `auth_required`: sem sessão salva, ou o Garmin recusou a sessão. O app pede
  para rodar `login` no Terminal.
- `login_failed`: e-mail, senha ou código recusados no `login`.
- `not_interactive`: `login` rodado fora de um Terminal.
- `cancelled`: Ctrl-C durante o login.
- `network`: sem internet, ou o Garmin não respondeu em 45 s. Tentar mais tarde.
- `rate_limited`: o Garmin pediu para esperar (HTTP 429).
- `garmin_unavailable`: erro 5xx do Garmin. Tentar mais tarde.
- `garmin_changed`: resposta em formato inesperado, ou o login mudou. O
  ajudante precisa de atualização.
- `usage`: argumentos inválidos (erro de programação no app).
- `internal`: qualquer outra falha; `detail` diz qual.

## Sessão

Os tokens ficam em `~/Library/Application Support/Gota/garmin/` (pasta 700,
arquivos `oauth1_token.json` e `oauth2_token.json` com permissão 600), fora do
repositório. O token de acesso dura pouco: quando o Garmin o recusa, a
biblioteca o renova sozinha e o ajudante regrava os arquivos. Quando a renovação
também é recusada, a resposta é `auth_required` e nenhum login automático é
tentado, o que evita bloqueio da conta. Para sair, basta apagar a pasta.
`GOTA_GARMIN_TOKEN_DIR` troca a pasta; `GOTA_GARMIN_API_BASE` só existe para os
testes.

## Diferenças em relação à biblioteca

O ajudante chama os mesmos endereços que a biblioteca usa, mas sem as funções
prontas de hidratação dela, por três motivos:

- `getDailyHydration` dá erro quando o dia tem 0 ml e devolve onças em vez de
  ml.
- `updateHydrationLogOunces` grava o horário em UTC rotulado como horário local,
  o que joga a garrafa para outro horário (e, perto da meia-noite, para outro
  dia).
- A biblioteca escreve avisos na saída padrão; o ajudante os desvia para a saída
  de erro.

## Roteiro de validação com a conta real

1. `cd garmin && npm ci`
2. `node gota-garmin.mjs login` e digitar e-mail, senha e código.
3. `node gota-garmin.mjs get $(date +%F)` e comparar `ml` com o app Garmin
   Connect.
4. `node gota-garmin.mjs add 50 $(date +%FT%T)` e conferir que `total_ml` subiu
   50 e que a entrada aparece no app e no relógio.
5. Desfazer com `node gota-garmin.mjs add -50 $(date +%FT%T)` e confirmar com
   `get` que o total voltou. Se o Garmin recusar o valor negativo, apagar a
   entrada pela tela de hidratação do app Garmin Connect.
