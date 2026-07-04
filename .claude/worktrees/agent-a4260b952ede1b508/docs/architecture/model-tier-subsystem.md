# Architecture — Model-Tier-Subsystem (Cost-Mode, Token-Hebel)

> **Bindend.** Diese Spec beschreibt **wie** das `agent-flow`-Plugin die **Modellwahl je Agent** über einen pro-Lauf umschaltbaren **Cost-Mode** steuert — additiv und orthogonal zu allen anderen Achsen (Sprache, DB, Framework/Build, Migration-Tool). Ziel: ein Lauf ist zwischen *token-sparsam* (Prototyp) und *maximaler Qualität* (kritischer Review/Test/Retro) wählbar, ohne Agenten-Definitionen anzufassen. Abweichungen sind Review-Kriterium.

---

## 1. Zweck & Scope

**Zweck.** Der Betrieb läuft interaktiv unterm Claude-Abo (CONCEPT §1) — pro-Token-kostenfrei, aber mit **Nutzungs-Limits** (5h-/Wochen-Fenster). Ohne Steuerung läuft jeder Agent immer auf seinem im Frontmatter fest verdrahteten Modell; ein langer `/flow`-Lauf kann so die Limits sprengen. Das Model-Tier-Subsystem macht die Modellwahl zu einem **bewussten Hebel pro Lauf**:

- **Sparsam** (`low-cost`) für Wegwerf-/Explorations-Läufe → günstigere Modelle, besonders für die mechanischen Rollen.
- **Normal** (`balanced`) für den Alltag → exakt der bisherige Zustand.
- **Voll** (`max-quality`) wenn Token verfügbar sind und ein erstklassiger Review/Test/Retro gewünscht ist → die teuersten Modelle für die qualitäts-kritischen Rollen.

**Motivation (begründet).**

- **Modell ≠ Rolle-fix.** Welches Modell für eine Rolle angemessen ist, hängt vom Ziel des Laufs ab, nicht nur von der Rolle. Ein fixes Frontmatter-Modell bildet das nicht ab.
- **Kein Regress.** `balanced` muss bitgenau dem Verhalten *vor* diesem Subsystem entsprechen — die Spalte `balanced` der Matrix == das `model:`-Frontmatter jedes Agenten.
- **Eine Stelle der Wahrheit.** Die Modell-Zuordnung darf nicht über 11 Frontmatter verstreut justiert werden müssen; sie lebt in **einer** pflegbaren Matrix.

**Out of Scope.**

- **Pro-Item-Modellwahl** (unterschiedliche Modi für einzelne Board-Items im selben Lauf). Der Modus gilt **pro Lauf**, einheitlich für alle Dispatches.
- **Andere Token-Hebel** (durchgereichte Kontextgröße, Iterationszahl, Parallelität). Dieses Subsystem steuert ausschließlich die **Modellwahl**.
- **Automatische Modus-Wahl** anhand von Limit-Telemetrie. Der Modus wird explizit gesetzt (Argument/Profil), nicht geraten.

## 2. Die vier Modi

| Modus | Wann | Wirkung |
|---|---|---|
| `low-cost` | Wegwerf-Prototyp, Board grob durchziehen, Token knapp | Mechanik-Rollen auf das günstigste Modell, Denk-Rollen heruntergestuft |
| `balanced` | **Default** — Normalbetrieb | == Agent-Frontmatter; **kein** `model`-Override |
| `max-quality` | Token verfügbar, „richtig guter" Review/Test/Retro | Qualitäts-kritische Rollen auf das teuerste Modell (`opus`) |
| `frontier` | **Opt-in** (nie Default) — neueste Frontier-Klasse `fable` bewusst gewünscht | Top-Reasoning-Rollen auf `fable` (über `opus`); übrige wie `max-quality`. Getrennt von `max-quality`, da `fable` kein Extended Thinking hat |

Kurzformen (normalisiert): `low` → `low-cost`, `max`/`high` → `max-quality`, `mid`/`std` → `balanced`, `front` → `frontier`. Unbekannter Wert → `balanced` + einzeiliger Hinweis (nie raten). **`frontier` ist nie Fallback/Default** — nur durch explizites `--cost frontier`/`front` oder `cost_mode: frontier`.

## 3. Vertrag: die Rolle×Modus-Matrix

Die **maßgebliche** Rolle×Modus→Modell-Zuordnung ist die Tabelle in **`knowledge/model-tiers.md`** (Single Source). Dieses Architektur-Doc legt nur die **Invarianten** der Matrix fest; die konkreten Modell-Werte werden dort gepflegt:

- **Zeilen = Agenten-Rollen** (architekt, requirement, retro, teamLeader, reviewer, tester, dba, coder, designer, train, cicd).
- **Spalten = die vier Modi.**
- **Invariante I1:** Spalte `balanced` == `model:`-Frontmatter der jeweiligen Rolle (Verifikation: Frontmatter-Diff gegen die balanced-Spalte).
- **Invariante I2:** je Rolle gilt `low-cost ≤ balanced ≤ max-quality ≤ frontier` in der Kosten-/Fähigkeitsordnung (`haiku < sonnet < opus < fable`) — ein Modus dreht nie *gegen* seine Richtung.
- **Invariante I3:** jede via `/flow` o.ä. dispatchbare Rolle hat eine Matrix-Zeile.

## 4. Auflösung des aktiven Modus (Präzedenz, höchste zuerst)

1. **Lauf-Argument** `--cost <mode>` am Skill (`/flow --cost max`, `/requirement --cost low …`).
2. **Projekt-Default** `cost_mode:` aus `.claude/profile.md`.
3. **Fallback** `balanced`.

`frontier` ist **explizit opt-in**: es wird nur durch `--cost frontier`/`front` (Stufe 1) oder `cost_mode: frontier` (Stufe 2) aktiv und ist **nie** der Fallback (Stufe 3 ist immer `balanced`). Ein unbekannter Wert fällt auf `balanced`, nie auf `frontier`.

Der Modus wird **einmal pro Lauf** aufgelöst (in der Setup-Phase des Skills) und gilt für **alle** Dispatches desselben Laufs.

## 5. Override-Mechanik beim Dispatch

```
model = (cost_mode == "balanced") ? <kein Override>        // Frontmatter gilt
                                  : Matrix[rolle][cost_mode]
```

- Der `model`-Parameter des Task-Tools nimmt `opus | sonnet | haiku | fable` (`fable` empirisch als Override bestätigt, 2026-06-10). Präzedenz: **Override > Frontmatter > Session-Erbe**.
- Bei `balanced` setzt der Skill **keinen** `model`-Parameter (das Frontmatter bleibt wirksam) — so ist `balanced` garantiert regress-frei.
- **Konsumenten:** `/flow` wendet den Override auf jeden Agenten im Build-Loop (§3–§4) **und** auf `cicd` beim SHIP-Dispatch (§5) an. Die Single-Dispatch-Skills `/requirement`, `/retro`, `/train` wenden ihn auf ihren einen Agenten an.

## 6. Profil-Integration

- `.claude/profile.md` trägt `cost_mode: balanced` (Default). Enum: `low-cost | balanced | max-quality | frontier` (`frontier` opt-in, nie implizit).
- Geschrieben von `new-project` (Bootstrap) aus den `templates/*/profile.md` (die den Key tragen). `adopt` erbt ihn über das Template; ein fehlender Key wird vom Loader als `balanced` interpretiert (Backwards-Compat — bestehende Profile ohne den Key verhalten sich unverändert).

## 7. Zusammenspiel mit dem dev-gui

Das `dev-gui` (GUI der Fabrik) injiziert den Modus nur als **`--cost <mode>`-Flag** in die komponierte Befehlszeile (Selector für `flow`/`requirement`/`train`; `balanced` → kein Flag). Die **Modell-Auflösung liegt allein hier** in agent-flow; das dev-gui kennt die Matrix nicht. Vertrag dev-gui-seitig: `dev-gui/docs/specs/flow-trigger.md` (AC8 Backend-Enum-Validierung, AC9 Selector).

## 8. Verifikation / Review-Kriterien

- I1 prüfbar: `balanced`-Spalte gegen die elf `agents/*.md`-`model:`-Frontmatter diffen — müssen identisch sein.
- I3 prüfbar: jede dispatchbare Rolle hat eine Matrix-Zeile.
- Skill-Konformität: `/flow`, `/requirement`, `/retro`, `/train` lösen den Modus nach §4 auf und setzen den Override nach §5 (bei `balanced` keinen).
- Drift-Gate: eine Änderung der Modell-Zuordnung gehört in `knowledge/model-tiers.md` (+ ggf. dieses Doc), nicht ins Frontmatter.
