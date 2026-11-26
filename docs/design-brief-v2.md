# Water Tracker v2 — brief de design (para Claude Design)

> Cole o bloco abaixo como primeira mensagem no Claude Design. Anexe 2 capturas:
> o painel
> aberto (claro e escuro) e a barra de menus com a gota. Para capturar o painel:
> abra-o,
> `⌘⇧4`, espaço, clique no painel.

---

## Prompt

Você vai redesenhar o painel de um app nativo de macOS chamado **Water Tracker**: um
utilitário que vive só na barra de menus (ícone de gota + "2/4") e lembra de
beber água, contando garrafas por dia. Funcionalidade está pronta e aprovada. O
trabalho é **só visual**, e o resultado precisa ser implementável em SwiftUI
puro, sem assets além do ícone do app.

### Contexto técnico (restrições duras)

- Painel é um `MenuBarExtra` estilo `.window`: já vem com fundo de material do
  sistema, vibrancy e dark mode automáticos. Não desenhe fundo próprio.
- Largura alvo 240–260 pt. Altura: a menor possível. Componentes nativos:
  `Button` (`.bordered`, `.borderedProminent`, `.borderless`), `Stepper`,
  `Toggle`, `DisclosureGroup`, `Divider`, SF Symbols, SF Pro com text styles do
  sistema (`.headline`, `.body`, `.callout`, `.caption`).
- **Uma única cor de acento**: systemBlue fixo (`Color.waterTrackerAccent` +
  `.tint(.waterTrackerAccent)` na raiz do painel), não `Color.accentColor` — este segue o
  acento do macOS e com "Grafite" deixava o botão e a barra cinzas. Todo o resto em
  cores semânticas do sistema (`.primary`, `.secondary`, `.quaternary`). Hoje há
  três tons de azul diferentes (gráfico, anel, botão) e isso precisa sumir.
- Sem ícones custom, sem imagens, sem gradientes chamativos. Padrão Apple HIG,
  discreto, como um painel de Controle de Wi-Fi ou Bateria.

### O que existe hoje (e o que está errado)

1. Header "Water Tracker · Hoje, 14 de out." → data é ruído, remover.
2. Anel de progresso 120 pt com "0/4" e "0,0 L de 2,0 L" → grande demais para
   representar 4 garrafas; quero algo bem menor e mais simples (ex.: 4
   pontos/gotas que preenchem, barra fina, ou anel ≤ 56 pt).
3. Botão "+1 garrafa" `.borderedProminent .large` largura total + "−1" do mesmo
   tamanho → muito grande, cor feia; "−1" deve ser secundário e discreto (ícone
   pequeno, texto `.borderless`, ou aparecer só em hover).
4. Linha "Próximo lembrete às HH:mm" com ícone de sino → manter, mais discreta.
5. Faixa de 7 barras (últimos 7 dias) → gostei da ideia, mas quero bem mais
   simples ou escondida. O que importa é um **streak**: dias seguidos com meta
   batida.
6. `DisclosureGroup("Ajustes")` com 5 steppers, 2 toggles e "Testar lembrete" →
   pode continuar colapsado; proponha se vale mover para um ícone de engrenagem.
7. Rodapé com "Sair".

### Entregáveis

**Rodada 1 — exploração:** 3 variantes do painel no estado "2 de 4 garrafas",
modo escuro, em escala 1:1 (largura 240–260 pt). Cada uma com um conceito claro,
ex.: (A) mínima em texto, (B) 4 gotas que preenchem, (C) barra fina + streak. Me
pergunte qual seguir.

**Rodada 2 — refinamento da escolhida:** os 5 estados do painel: 0 garrafas ·
parcial · meta batida · notificações desativadas · Ajustes expandido. Mais o
modo claro de um deles.

**Rodada 3 — ícone do app:** ícone de gota para macOS (squircle padrão,
1024×1024), em azul do sistema sobre fundo claro ou branco sobre azul. Aparece
em Ajustes do Sistema e nas notificações. Exportar PNG 1024.

**Handoff final (markdown + PNGs):** spec que um dev implementa em SwiftUI sem
me perguntar nada:

- layout por seção com medidas em pt (padding, spacing, tamanhos);
- tipografia por elemento usando text styles do sistema;
- cores por elemento usando nomes semânticos (`accent`, `primary`, `secondary`,
  `quaternary`); zero hex além do ícone;
- mapeamento de cada elemento para o componente SwiftUI correspondente;
- regra do streak (como conta, quando zera, como exibe);
- o que muda em cada um dos 5 estados.

Não altere funcionalidades, textos de ação ("+1 garrafa", "Bebi uma garrafa",
"Lembrar em 15 min") nem a lógica dos lembretes.

---

## Quando voltar

Traga o markdown do handoff e os PNGs para esta pasta — o handoff final ficou
em `~/projects/water-tracker/design/water-tracker-handoff.md`, não em `docs/` — e abra a
demanda com Futaba: "implementa o handoff de design v2 do Water Tracker". O bug
funcional já conhecido na época (o painel mostra "Notificações desativadas"
mesmo com permissão concedida; status precisa ser relido via
`getNotificationSettings` ao abrir o painel, não só no launch) foi corrigido no
commit `2b724ec` ("fix: re-read notification authorization when panel
opens").
