# Knowledge Pack: model-tiers (Cost-Modi / Modell-Auswahl je Rolle)

> **last_curated:** 2026-07-01 — Frische-Signal + Cooldown-State für `/train model-tiers` (Spec `docs/specs/model-tier-curator.md`). Der Curator setzt das Datum bei **jedem** Lauf auf heute; Cooldown = max. 1× pro Kalendermonat (`--force` umgeht). `never`/leer ⇒ kein Cooldown, erster Lauf erlaubt.
>
> **primary_sources** (autoritativ — **ausschließlich** diese für die Klassen-/Tier-Kuration; `docs.claude.com`-Pfade leiten per 302 auf `platform.claude.com`):
> - *Models overview* — https://platform.claude.com/docs/en/about-claude/models/overview
> - *Model deprecations / Lifecycle* — https://platform.claude.com/docs/en/about-claude/model-deprecations
> - *Pricing* (**nur informativ** für die relative Tier-Einordnung, nie Dollar-Zielwert — ADR-001: Abo, keine API-Kosten) — https://platform.claude.com/docs/en/about-claude/pricing
>
> **non_sources:** Blogs, Foren, Drittanbieter-Tabellen, Social-Media — nie als Beleg zitieren.

> **Zweck.** Ein **Schalter** (`cost_mode`) steuert, mit welchem Modell jeder Agent dispatcht wird —
> token-schonend für Prototypen, voll aufgedreht für kritische Reviews/Tests/Retros. Die Skills
> (`/flow`, `/requirement`, `/retro`, `/train`) lesen diese Matrix und geben beim **Task-Dispatch**
> einen `model`-**Override** mit. Ohne Override gilt das `model:`-Frontmatter des Agenten (= `balanced`).

## Die vier Modi

| Modus | Wann | Effekt |
|---|---|---|
| `low-cost` | Wegwerf-Prototyp, Board grob durchziehen, Token knapp | Mechanik-Rollen auf `haiku`, Denk-Rollen auf `sonnet` — maximal sparsam |
| `balanced` | **Default** — Normalbetrieb | Exakt der heutige Zustand (= Agent-Frontmatter); kein Override |
| `max-quality` | Token satt, „richtig guter" Review/Test/Retro gewünscht | Qualitäts-kritische Rollen auf `opus` |
| `frontier` | **Opt-in** (nie Default) — neueste Frontier-Klasse `fable` bewusst gewünscht | Top-Reasoning-Rollen auf `fable` (über `opus`); übrige Rollen wie `max-quality`. `fable` ist ~2× teurer als `opus` und hat **kein** Extended Thinking — daher selektiv. |

## Tier-Matrix (Rolle × Modus)

| Rolle | `low-cost` | `balanced` | `max-quality` | `frontier` |
|---|---|---|---|---|
| architekt   | sonnet | opus   | opus   | **fable**  |
| requirement | sonnet | opus   | opus   | **fable**  |
| retro       | sonnet | opus   | opus   | opus   |
| teamLeader  | sonnet | opus   | opus   | opus   |
| reviewer    | sonnet | sonnet | opus   | **fable**  |
| tester      | haiku  | sonnet | opus   | opus   |
| dba         | haiku  | sonnet | opus   | opus   |
| estimator   | haiku  | sonnet | opus   | opus   |
| coder       | haiku  | sonnet | opus   | **fable**  |
| designer    | haiku  | sonnet | opus   | opus   |
| train       | sonnet | sonnet | opus   | opus   |
| cicd        | haiku  | sonnet | sonnet | sonnet |

**`frontier`-Spalte (Variante b „Selektiv", Designentscheidung D1):** nur die Top-Reasoning-Rollen
(`architekt`, `requirement`, `reviewer`, `coder`) laufen auf `fable`; die übrigen behalten ihren
`max-quality`-Wert. Begründung: `fable` ist ~2× teurer (Kontingent) und hat **kein** Extended
Thinking, während `opus` ein Adaptive/Extended-Reasoning-Profil hat — „fable überall" ist daher
nicht pauschal besser. Spec: `docs/specs/frontier-cost-mode.md` (V3/AC3).

**Lesart.** Spalte `balanced` == das `model:`-Frontmatter jedes Agenten (kein Regress). Im Modus
`balanced` gibt der Skill **keinen** `model`-Override mit — der Agent läuft auf seinem Frontmatter-Wert.
In `low-cost`/`max-quality`/`frontier` schlägt der Skill die Rolle in dieser Tabelle nach und übergibt den
Treffer als `model`-Override beim Task-Dispatch (Präzedenz: **Override > Frontmatter > Session-Erbe**).

## Auflösung des aktiven Modus (Präzedenz, höchste zuerst)

1. **Lauf-Argument** `--cost <mode>` an den Skill (`/flow --cost max`, `/requirement --cost low …`).
2. **Projekt-Default** `cost_mode:` aus `.claude/profile.md`.
3. **Fallback** `balanced` (wenn weder Argument noch Profil-Key vorhanden).

Gültige Werte: `low-cost` | `balanced` | `max-quality` | `frontier`. Kurzformen erlaubt und gleichbedeutend:
`low` → `low-cost`, `max`/`high` → `max-quality`, `mid`/`std` → `balanced`, `front` → `frontier`. Unbekannter Wert →
**nicht raten**: auf `balanced` zurückfallen und einen einzeiligen Hinweis ausgeben — **nie** auf `frontier`
(opt-in, nur durch explizites `--cost frontier`/`front` oder `cost_mode: frontier`).

## Override-Mechanik beim Dispatch

Beim `Task`-Dispatch eines Agenten:

```
model = (cost_mode == "balanced") ? <kein Override>  // Frontmatter gilt
                                  : <Matrix[rolle][cost_mode]>
```

- Der `model`-Parameter des Task-Tools nimmt `opus` | `sonnet` | `haiku` | `fable` (`fable` empirisch als Override bestätigt, 2026-06-10).
- Im Build-Loop (`/flow` §3) gilt der Modus für **alle** Dispatch-Runden des Laufs gleich
  (coder, reviewer, dba, tester, cicd, estimator) — der Modus wird einmal in §0 aufgelöst und durchgereicht.
- Single-Dispatch-Skills (`/requirement`, `/retro`, `/train`) wenden ihn auf ihren einen Agenten an.

## Hinweise

- **Modell ≠ einziger Token-Hebel.** Was an einen Subagenten durchgereicht wird (Kontextgröße),
  die Iterationszahl (Build-Loop max. 3) und parallele Dispatches zählen ebenso. Dieser Pack
  steuert nur die Modellwahl.
- **`low-cost` ist bewusst aggressiv** (`coder`/`tester` auf `haiku`). Für echte Features, die
  landen sollen, ist `balanced` oder `max-quality` die richtige Wahl — `low-cost` ist für
  Wegwerf-/Explorations-Läufe gedacht.
- **Matrix justieren:** Diese Tabelle ist der **einzige** Ort der Wahrheit. Frontmatter der Agenten
  NICHT ändern (es ist der `balanced`-Default). Modi/Rollen hier pflegen.

## Modell-Klasse `fable` (eingebunden via `frontier`, seit 2026-06-10)

**Befund (autoritativ verifiziert, Models overview + Pricing — primary_sources):**
Claude Fable 5 (`claude-fable-5`) ist seit 9. Juni 2026 GA auf Claude API, Bedrock, Vertex AI und
Microsoft Foundry. Die offizielle Beschreibung laut Models overview:

> "Claude Fable 5 (`claude-fable-5`) is Anthropic's most capable widely released model."

Preislich liegt `fable` **über** dem opus-Tier: $10/$50 MTok (Input/Output) vs. opus $5/$25 MTok.
Kein Extended Thinking; Adaptive Thinking "always on" (laut Tabelle: `fable`: Extended Thinking =
No, Adaptive Thinking = Yes — identisch zu Claude Mythos 5). Quellen:
- Models overview: https://platform.claude.com/docs/en/about-claude/models/overview
- Pricing: https://platform.claude.com/docs/en/about-claude/pricing

**Status:** `fable` ist als reguläre Klasse über den opt-in-Modus **`frontier`** eingebunden (Spalte
oben, Klassen-Ordnung `haiku < sonnet < opus < fable`). Bewusst **getrennt** von `max-quality`
(bleibt `opus`): Fable 5 hat **kein** Extended Thinking, während Opus 4.8 ein Adaptive/Extended-
Reasoning-Profil hat — `frontier` ist daher kein pauschales „besser als max-quality", sondern eine
opt-in Frontier-Wahl. Verfügbarkeit als `model`-Override empirisch bestätigt (2026-06-10).
Spec der Einbindung: `docs/specs/frontier-cost-mode.md`. *(Der frühere Scope-Cut-Hinweis ist mit
dieser Einbindung aufgelöst.)*

## Kuration 2026-07-01 (reiner Frischelauf, kein Klassen-/Tier-Delta)

**Soll-Ist-Abgleich gegen alle drei primary_sources** (Models overview, Model deprecations,
Pricing — Stand 2026-07-01): kein V3-Trigger zutreffend.

- **(a) Neue Klasse/Tier:** keine. `claude-mythos-5`/`claude-mythos-preview` sind laut Models
  overview zwar sichtbar, aber explizit „not generally available" / „invitation-only" ([Project
  Glasswing](https://anthropic.com/glasswing)) — keine breit verfügbare Klasse neben
  `haiku`/`sonnet`/`opus`/`fable`, daher keine Matrix-Relevanz.
- **(b) Deprecation/Umbenennung einer verwendeten Klasse:** keine. Alle vier in der Matrix
  verwendeten Klassen-Namen (`haiku`, `sonnet`, `opus`, `fable`) sind weiterhin aktiv geführte
  Klassen; lediglich Punktversionen wechseln (Opus 4.8 aktiv, Opus 4.1 deprecated → Retirement
  5. Aug 2026 laut [Model deprecations](https://platform.claude.com/docs/en/about-claude/model-deprecations#model-status) —
  betrifft nur eine alte Punktversion der Klasse `opus`, nicht die Klasse selbst → kein Trigger
  nach AC4).
- **(c) Tier-Rebalancing:** keines. Preis-Ordnung laut
  [Pricing](https://platform.claude.com/docs/en/about-claude/pricing#model-pricing) unverändert
  `haiku` ($1/$5 MTok) < `sonnet` ($3/$15 Standard ab 1.9.2026, $2/$10 introduktorisch bis
  31.8.2026) < `opus` ($5/$25 MTok) < `fable` ($10/$50 MTok) — die Klassen-Reihenfolge I2
  (`low-cost ≤ balanced ≤ max-quality`) bleibt konsistent mit der Matrix.

**Invarianten geprüft:** I1 (balanced == Agent-Frontmatter, unverändert), I2 (Klassen-Ordnung
`haiku ≤ sonnet ≤ opus ≤ fable` weiterhin preislich/leistungsmäßig konsistent), I3 (Rollen-Zeilen
unverändert vollständig — kein neuer dispatchbarer Agent seit 2026-06-15 bekannt). Keine
Invariante verletzt.

`last_curated` auf 2026-07-01 aktualisiert (Frischesignal, AC5/AC9); Matrix inhaltlich
unverändert.
