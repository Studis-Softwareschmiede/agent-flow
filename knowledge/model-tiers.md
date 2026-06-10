# Knowledge Pack: model-tiers (Cost-Modi / Modell-Auswahl je Rolle)

> **last_curated:** never — Frische-Signal + Cooldown-State für `/train model-tiers` (Spec `docs/specs/model-tier-curator.md`). Der Curator setzt das Datum bei **jedem** Lauf auf heute; Cooldown = max. 1× pro Kalendermonat (`--force` umgeht). `never`/leer ⇒ kein Cooldown, erster Lauf erlaubt.
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

## Die drei Modi

| Modus | Wann | Effekt |
|---|---|---|
| `low-cost` | Wegwerf-Prototyp, Board grob durchziehen, Token knapp | Mechanik-Rollen auf `haiku`, Denk-Rollen auf `sonnet` — maximal sparsam |
| `balanced` | **Default** — Normalbetrieb | Exakt der heutige Zustand (= Agent-Frontmatter); kein Override |
| `max-quality` | Token satt, „richtig guter" Review/Test/Retro gewünscht | Qualitäts-kritische Rollen auf `opus` |

## Tier-Matrix (Rolle × Modus)

| Rolle | `low-cost` | `balanced` | `max-quality` |
|---|---|---|---|
| architekt   | sonnet | opus   | opus   |
| requirement | sonnet | opus   | opus   |
| retro       | sonnet | opus   | opus   |
| teamLeader  | sonnet | opus   | opus   |
| reviewer    | sonnet | sonnet | opus   |
| tester      | haiku  | sonnet | opus   |
| dba         | haiku  | sonnet | opus   |
| coder       | haiku  | sonnet | opus   |
| designer    | haiku  | sonnet | opus   |
| train       | sonnet | sonnet | opus   |
| cicd        | haiku  | sonnet | sonnet |

**Lesart.** Spalte `balanced` == das `model:`-Frontmatter jedes Agenten (kein Regress). Im Modus
`balanced` gibt der Skill **keinen** `model`-Override mit — der Agent läuft auf seinem Frontmatter-Wert.
In `low-cost`/`max-quality` schlägt der Skill die Rolle in dieser Tabelle nach und übergibt den
Treffer als `model`-Override beim Task-Dispatch (Präzedenz: **Override > Frontmatter > Session-Erbe**).

## Auflösung des aktiven Modus (Präzedenz, höchste zuerst)

1. **Lauf-Argument** `--cost <mode>` an den Skill (`/flow --cost max`, `/requirement --cost low …`).
2. **Projekt-Default** `cost_mode:` aus `.claude/profile.md`.
3. **Fallback** `balanced` (wenn weder Argument noch Profil-Key vorhanden).

Gültige Werte: `low-cost` | `balanced` | `max-quality`. Kurzformen erlaubt und gleichbedeutend:
`low` → `low-cost`, `max`/`high` → `max-quality`, `mid`/`std` → `balanced`. Unbekannter Wert →
**nicht raten**: auf `balanced` zurückfallen und einen einzeiligen Hinweis ausgeben.

## Override-Mechanik beim Dispatch

Beim `Task`-Dispatch eines Agenten:

```
model = (cost_mode == "balanced") ? <kein Override>  // Frontmatter gilt
                                  : <Matrix[rolle][cost_mode]>
```

- Der `model`-Parameter des Task-Tools nimmt `opus` | `sonnet` | `haiku`.
- Im Build-Loop (`/flow` §3) gilt der Modus für **alle** Dispatch-Runden des Laufs gleich
  (coder, reviewer, dba, tester, cicd) — der Modus wird einmal in §0 aufgelöst und durchgereicht.
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
