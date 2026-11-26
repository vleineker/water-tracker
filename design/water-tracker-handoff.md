# Gota — Handoff de design do painel (MenuBarExtra)

Spec para implementação em SwiftUI puro. Nenhum asset além do ícone do app. Nenhuma mudança de funcionalidade, de textos de ação nem da lógica de lembretes.

Referências visuais em `states/` (PNG @2x, 1:1 = 250 pt de largura) e `icon/`.

---

## 0. Regras globais

| Item | Valor |
|---|---|
| Container | `MenuBarExtra(... ) { PanelView() }.menuBarExtraStyle(.window)` — sem fundo próprio, sem `.background`, sem `.ultraThinMaterial`. O sistema dá material, vibrancy e dark mode. |
| Largura | `.frame(width: 250)` fixa |
| Altura | Intrínseca (hug). Estado base = **132 pt**; Ajustes expandido = **374 pt** |
| Padding externo | top 12 · leading/trailing 14 · bottom 6 |
| Spacing vertical entre seções | 8 (VStack raiz: `VStack(alignment: .leading, spacing: 8)`) |
| Fonte | SF Pro via text styles do sistema (nunca `.system(size:)`) |
| Cor de acento | `Color.gotaAccent` = `Color(nsColor: .systemBlue)`, aplicado também como `.tint(.gotaAccent)` na raiz do painel — único azul do painel. Fixado em systemBlue (não `Color.gotaAccent`) porque com o acento "Grafite" do macOS o "+1 garrafa" e a barra ficavam cinzas. Aparece em exatamente 3 lugares: fill da barra, pontos de streak com meta batida, botão `.borderedProminent` (mais o ícone da linha condicional "Nova versão", [5b]) |
| Demais cores | `.primary`, `.secondary`, `.quaternary` (fills), `Divider()` padrão |
| Ícones | SF Symbols, sempre `.imageScale(.small)` ou `font(.caption)` conforme tabela |
| Animação | `withAnimation(.easeOut(duration: 0.2))` ao mudar a barra e os pontos; `.animation(.easeInOut(duration: 0.2))` ao expandir Ajustes. Nada mais anima. |

**Hex zero** no painel. O único hex do projeto está no ícone (seção 6).

---

## 1. Layout por seção (estado base, de cima para baixo)

```
┌─ padding 12 ───────────────────────────────┐
│ [1] Header ............................ 16 │
│     spacing 8                              │
│ [2] Barra de progresso ................. 4 │
│     spacing 6                              │
│ [3] Litros · Streak ................... 13 │
│     spacing 8                              │
│ [4] Ações ............................. 22 │
│     spacing 8                              │
│ [5] Divider ............................ 1 │
│     spacing 8                              │
│ [6] Rodapé ............................ 20 │
└─ padding 6 ────────────────────────────────┘
                                    = 132 pt
```

### [1] Header — `HStack(alignment: .firstTextBaseline)`
| Elemento | Componente | Tipografia | Cor | Observações |
|---|---|---|---|---|
| "Gota" | `Text` | `.headline` | `.primary` | leading |
| (só em notif. off) `bell.slash` | `Image(systemName:)` | `.caption` | `.secondary` | 6 pt à direita de "Gota". Ver estado 4 |
| (só em meta batida) `checkmark.circle.fill` | `Image(systemName:)` | `.body` | `Color.gotaAccent` | 5 pt antes da contagem. Ver estado 3 |
| Contagem "**2** de 4 garrafas" | `Text` concatenado | `.body`; o número com `.fontWeight(.semibold)` | número `.primary`, resto `.secondary` | trailing (`Spacer()` entre) |

### [2] Barra de progresso
| Elemento | Componente | Medidas | Cor |
|---|---|---|---|
| Trilho | `Capsule()` | altura 4, largura total | `.quaternary` (`.fill(.quaternary)`) |
| Preenchimento | `Capsule()` sobreposto via `GeometryReader` ou `.overlay(alignment: .leading)` | altura 4, largura = `count / goal` × largura total | `Color.gotaAccent` |

Não usar `ProgressView` — o estilo linear nativo tem 6 pt e borda própria. Duas `Capsule` é mais fiel.

### [3] Litros · Streak — `HStack`
| Elemento | Componente | Tipografia | Cor |
|---|---|---|---|
| "1,0 L de 2,0 L" | `Text` | `.caption` | `.secondary` |
| `Spacer()` | | | |
| 7 pontos | `HStack(spacing: 3)` de `Circle().frame(width: 5, height: 5)` | — | ver regra do streak (seção 4) |
| 6 pt de gap, depois "3 dias" | `Text` | `.caption` | `.secondary` |

O grupo pontos + texto tem `.accessibilityElement(children: .combine)` e label "N dias seguidos com meta batida".

### [4] Ações — `HStack`
| Elemento | Componente | Estilo | Tipografia | Cor |
|---|---|---|---|---|
| "+1 garrafa" | `Button` | `.buttonStyle(.borderedProminent)`, `.controlSize(.regular)` — **não** `.large`, **não** full-width | sistema (`.body`, medium) | tint = accent (padrão) |
| `Spacer()` | | | | |
| "−1" | `Button` | `.buttonStyle(.borderless)`, `.controlSize(.regular)` | `.body` | `.foregroundStyle(.secondary)` |

Ambos mantêm as ações já existentes. Altura resultante 22 pt (regular). O "−1" fica oculto quando `count == 0` (ver estado 1) — ocultar, não desabilitar, para não sobrar um botão cinza.

**Confirmação de remoção:** tocar em "−1" não remove; troca a linha de ações por "Deseja realmente remover uma garrafa?" (`.caption`, `.secondary`) com "Cancelar" (`.bordered`, atalho Esc) e "Remover" (`.bordered`, sem tint — sem cor de alerta). Só "Remover" chama `store.add(-1)`. Confirmação inline (não `.alert`/`.confirmationDialog`) porque diálogos de sistema tiram o foco e fecham o popover da barra de menus. Fechar o painel cancela (`confirmingRemove = false` em `onDisappear`).

### [5] `Divider()`

### [5b] Nova versão (condicional)

Só aparece quando a release mais recente no GitHub (`releases/latest`, `tag_name` sem o "v") é numericamente maior que `CFBundleShortVersionString`. Checagem ao abrir o painel, no máximo 1x a cada 24 h; silenciosa em erro/offline (linha simplesmente não aparece). Fica logo acima do rodapé (abaixo de Ajustes, quando expandido).

| Elemento | Componente | Tipografia | Cor | Observações |
|---|---|---|---|---|
| `arrow.down.circle` + "Nova versão 1.1 disponível" | `Button` `.buttonStyle(.borderless)` com `HStack(spacing: 4)` | `.caption` | ícone `Color.gotaAccent`, texto `.secondary` | Clique abre `html_url` da release via `NSWorkspace.shared.open`. Sem fundo, sem cor de alerta. |

### [6] Rodapé — `HStack`
| Elemento | Componente | Estilo | Cor | Observações |
|---|---|---|---|---|
| Engrenagem | `Button { settingsExpanded.toggle() } label: { Image(systemName: "gearshape") }` | `.buttonStyle(.borderless)`, frame 20×20, `.imageScale(.medium)` | `.secondary` | Quando expandido: `.background(.quaternary, in: RoundedRectangle(cornerRadius: 5))` e ícone `.primary` |
| `Spacer()` | | | | |
| "Sair" | `Button` | `.buttonStyle(.borderless)` | `.foregroundStyle(.secondary)` | Mesma ação de hoje (`NSApp.terminate`). `.keyboardShortcut("q")` |

Para alinhar com as bordas do texto acima: engrenagem com `.padding(.leading, -4)` e "Sair" com `.padding(.trailing, -6)` (compensa o padding interno do `.borderless`).

---

## 2. Tipografia (resumo)

| Elemento | Text style | Peso |
|---|---|---|
| "Gota" | `.headline` | (bold, padrão do style) |
| Contagem — número | `.body` | `.semibold` |
| Contagem — "de 4 garrafas" | `.body` | regular |
| "1,0 L de 2,0 L", "3 dias" | `.caption` | regular |
| Botões "+1 garrafa", "−1", "Sair", "Testar lembrete" | padrão do `Button` (`.body`) | padrão |
| Cabeçalho "AJUSTES" | `.caption` | `.semibold`, `.textCase(.uppercase)` |
| Labels dos steppers/toggles | `.body` | regular |
| Valores dos steppers | `.body` | regular, `.secondary` |

---

## 3. Cores (resumo)

| Elemento | Cor semântica |
|---|---|
| "Gota", número da contagem, labels de Ajustes, ícone da engrenagem quando ativo | `.primary` |
| "de 4 garrafas", litros, "N dias", "−1", "Sair", engrenagem, `bell.slash`, valores dos steppers | `.secondary` |
| Trilho da barra, pontos sem meta, fundo da engrenagem ativa | `.quaternary` |
| Fill da barra, pontos com meta, anel de "hoje", botão prominente, `checkmark.circle.fill`, toggles ligados, ícone de "Nova versão" | `Color.gotaAccent` |
| Separadores | `Divider()` padrão |

Nenhuma cor "de sucesso" (verde) na meta batida: continua accent. Nenhuma cor de alerta.

---

## 4. Regra do streak

**Definição:** número de dias consecutivos, terminando **ontem ou hoje**, em que `count >= goal` ao final do dia.

- **Dia batido:** vale o último valor registrado no dia, não "em algum momento". Implementação: a cada mudança de `count`, gravar `metGoal[today] = count >= goal` (um "−1" depois de bater a meta desfaz o dia batido).
- **Como conta:** ao abrir o painel, percorrer de ontem para trás enquanto `metGoal[d] == true`; esse total é `streak`. Se `metGoal[today] == true`, `streak += 1`.
- **Quando zera:** quando existe um dia completo (ontem ou antes) sem meta. Hoje não zera o streak enquanto o dia não acabar — por isso o ponto de hoje é um anel, não um ponto vazio.
- **Mudança de meta:** usa a meta vigente em cada dia (gravar `metGoal` já resolvido, não recalcular retroativamente).

**Exibição (7 pontos, da esquerda para a direita = D-6 … hoje):**

| Dia | `metGoal` | Ponto |
|---|---|---|
| Passado | `true` | `Circle().fill(Color.gotaAccent)` |
| Passado | `false` / sem registro | `Circle().fill(.quaternary)` |
| Hoje | `false` | `Circle().strokeBorder(Color.gotaAccent, lineWidth: 1)` (anel) |
| Hoje | `true` | `Circle().fill(Color.gotaAccent)` |

Texto ao lado: `"\(streak) dias"` (`"1 dia"` no singular; `"0 dias"` quando zero — manter o texto, não esconder).

Isto substitui integralmente a faixa de 7 barras.

---

## 5. Os 5 estados (+ modo claro)

| # | Estado | O que muda em relação ao base (parcial) |
|---|---|---|
| 1 | **0 garrafas** | Contagem "**0** de 4 garrafas"; barra com fill de largura 0; litros "0,0 L de 2,0 L"; botão "−1" **oculto** (`if count > 0`). Ponto de hoje = anel. |
| 2 | **Parcial** (base) | Como descrito na seção 1. |
| 3 | **Meta batida** (`count >= goal`) | `checkmark.circle.fill` em accent (`.body`) 5 pt antes da contagem; barra 100 %; ponto de hoje preenchido; `streak` já inclui hoje; "+1 garrafa" troca para `.buttonStyle(.bordered)` (mesma ação, mesmo texto — só perde o destaque). "−1" continua visível. Se `count > goal`, barra fica em 100 % e a contagem mostra o número real ("5 de 4 garrafas"). |
| 4 | **Notificações desativadas** (toggle "Lembretes" off ou permissão negada) | `Image(systemName: "bell.slash")` `.caption` `.secondary` a 6 pt da direita de "Gota", com `.help("Lembretes desativados")`. Nada mais muda. |
| 5 | **Ajustes expandido** (`settingsExpanded == true`) | Entre o `Divider` [5] e o rodapé entra a seção de Ajustes (abaixo), seguida de outro `Divider()` e spacing 8. Engrenagem com fundo `.quaternary` e ícone `.primary`. Altura total 374 pt. Fecha ao clicar de novo na engrenagem; fechar o painel também colapsa (`settingsExpanded = false` em `onDisappear`). |
| — | **Modo claro** | Nada a fazer: todas as cores são semânticas. |

### Seção de Ajustes (estado 5) — `VStack(alignment: .leading, spacing: 6)`

| Linha | Componente | Altura | Notas |
|---|---|---|---|
| "AJUSTES" | `Text` `.caption` `.semibold` `.textCase(.uppercase)` `.secondary` | 13 | |
| 5 steppers (manter os existentes, mesma ordem e rótulos) | `HStack { Text(label); Spacer(); Text(valor).foregroundStyle(.secondary); Stepper("", value:…).labelsHidden() }` | 20 cada | gap 8 entre valor e `Stepper`; `.controlSize(.small)` no `Stepper` |
| 2 toggles (os existentes) | `Toggle(label, isOn:)` `.toggleStyle(.switch)` `.controlSize(.small)` | 20 cada | label `.body` `.primary` |
| espaçador | `Spacer().frame(height: 2)` | 2 | |
| "Testar lembrete" | `Button` `.buttonStyle(.bordered)` `.controlSize(.regular)` | 22 | alinhado à esquerda, largura natural |

Isto substitui o `DisclosureGroup("Ajustes")`. Se preferir manter o `DisclosureGroup`, use-o com `.disclosureGroupStyle` padrão, label "Ajustes" `.body`, no lugar da engrenagem — o conteúdo interno é o mesmo. A versão com engrenagem é a desenhada.

---

## 6. Ícone do app

Arquivos em `icon/`:

- `AppIcon-white-on-blue.png` — **recomendado**. Gota branca sobre azul do sistema. Lê bem em 16 pt nas notificações e em Ajustes do Sistema.
- `AppIcon-blue-on-white.png` — alternativa. Gota azul sobre branco; mais discreto no Dock, mas some sobre fundos claros em tamanhos pequenos.

Especificação (único lugar do projeto com hex):

| Item | Valor |
|---|---|
| Canvas | 1024 × 1024, fundo transparente |
| Forma | Superelipse (squircle) 824 × 824 centrada, n = 5 |
| Sombra | dy 12, blur 14, preto 28 % (padrão Big Sur) |
| Fundo (opção 1) | gradiente vertical sutil `#1A8CFF` → `#0070F0` (≈ systemBlue) |
| Fundo (opção 2) | `#FFFFFF` → `#F2F2F7`, rim 2 px preto 8 % |
| Glifo | gota 470 pt de altura, centro em (512, 520), largura 72 % da altura, ponta superior com curva suave, base circular |
| Cor do glifo | opção 1 `#FFFFFF` · opção 2 `#007AFF` |

Uso: arrastar o PNG 1024 no slot "Mac 1024pt" do `AppIcon` no Asset Catalog (Xcode gera os demais tamanhos). O SVG fonte de cada variante está ao lado do PNG.

---

## 7. Esqueleto SwiftUI (referência, não normativo)

```swift
struct PanelView: View {
    @ObservedObject var model: WaterModel
    @State private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            progressBar
            litersAndStreak
            actions
            Divider()
            if settingsExpanded {
                settings
                Divider()
            }
            footer
        }
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .frame(width: 250)
        .tint(.gotaAccent)
        .onDisappear { settingsExpanded = false }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Gota").font(.headline)
            if !model.remindersEnabled {
                Image(systemName: "bell.slash")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Lembretes desativados")
            }
            Spacer()
            if model.goalMet {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body).foregroundStyle(Color.gotaAccent)
            }
            (Text("\(model.count)").fontWeight(.semibold)
             + Text(" de \(model.goal) garrafas").foregroundStyle(.secondary))
                .font(.body)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.gotaAccent)
                    .frame(width: geo.size.width * model.progress) // min(count/goal, 1)
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.2), value: model.count)
    }

    private var litersAndStreak: some View {
        HStack(spacing: 6) {
            Text(model.litersLabel).font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 3) {
                ForEach(model.last7Days) { day in
                    Circle()
                        .fill(day.met ? Color.gotaAccent : Color.clear)
                        .overlay {
                            if !day.met {
                                if day.isToday { Circle().strokeBorder(Color.gotaAccent, lineWidth: 1) }
                                else { Circle().fill(.quaternary) }
                            }
                        }
                        .frame(width: 5, height: 5)
                }
            }
            Text(model.streakLabel).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack {
            Group {
                if model.goalMet {
                    Button("+1 garrafa", action: model.add).buttonStyle(.bordered)
                } else {
                    Button("+1 garrafa", action: model.add).buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.regular)
            Spacer()
            if model.count > 0 {
                Button("−1") { model.confirmingRemove = true }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .padding(.trailing, -6)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button { withAnimation(.easeInOut(duration: 0.2)) { settingsExpanded.toggle() } } label: {
                Image(systemName: "gearshape").imageScale(.medium)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(settingsExpanded ? .primary : .secondary)
                    .background(settingsExpanded ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.borderless)
            .padding(.leading, -4)
            Spacer()
            Button("Sair") { NSApp.terminate(nil) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .keyboardShortcut("q")
                .padding(.trailing, -6)
        }
    }
}
```

---

## 8. Checklist de aceite

- [ ] Largura 250 pt; altura 132 pt no estado base, 374 pt com Ajustes
- [ ] Nenhum `Color(hex:)`, `Color(red:green:blue:)` ou `.blue` solto no painel — só `Color.gotaAccent` (systemBlue fixo) e cores semânticas
- [ ] Nenhum `.background` no container (o `MenuBarExtra` fornece o material)
- [ ] Nenhum `.font(.system(size:))` — só text styles
- [ ] "−1" some em 0 garrafas; "+1 garrafa" vira `.bordered` ao bater a meta
- [ ] `bell.slash` aparece quando lembretes estão desativados
- [ ] Streak conta conforme seção 4 e o ponto de hoje é anel até bater a meta
- [ ] Alternar modo claro/escuro no sistema não exige nenhum código
