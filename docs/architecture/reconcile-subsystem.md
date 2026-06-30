# Reconcile-Subsystem — wiederkehrender Code→Doc-Drift-Abgleich

> **Status:** akzeptiert (Stufe 1). Quer-Achse wie `traceability-subsystem.md` / `model-tier-subsystem.md`.
> **Source of Truth** für den *rückwärtigen* Abgleich „der Code ist weiter als die Doku". Sprach-**neutral**:
> dieses Dokument definiert den Vertrag; die Erkennung selbst nutzt den bestehenden `reviewer`-Audit-Modus
> + die `/adopt`-Maschinerie (Spec-aus-Code-Ableitung). Kein neuer Agent, kein eigenes Skill.

## 1. Zweck & Problem

Die `docs/` (Konzept → Architektur → Spec) sind die durable Source of Truth (CONCEPT §4d). In der Praxis
**eilt der Code ihr aber voraus**: Direkt-Commits außerhalb von `/flow`, Bestand vor der Adoption, manuelle
Hotfixes, fremder Upstream-Code. Diese Abweichung akkumuliert **unbemerkt** — die Doku rottet still.

Heute decken zwei Mechanismen je nur einen Teil ab; **die wiederkehrende Aufholung fehlt**:

| Mechanismus | Richtung | Wann | Deckt | Lücke |
|---|---|---|---|---|
| **Drift-Gate** (`reviewer`, CONCEPT §4d) | verhindert Code-ohne-Spec | jeder `/flow`-PR | **neue** Drift im Fluss | nur was durch `/flow` + `reviewer` läuft |
| **Spec-aus-Code** (`/adopt` §2) | Code→Doc | **einmalig** bei Adoption | initialer Doc-Stand | kein Wiederholungs-Lauf |
| **`/adopt reconcile`** (dies) | Code→Doc | **on-demand / periodisch** | **akkumulierte** Drift | — |

`reconcile` ist das **rückwärtige, wiederkehrende Gegenstück** zum vorwärtigen per-PR-Drift-Gate.

## 2. Leitprinzip

Drei Schritte, klare Hoheits-Trennung — **wie überall in der Fabrik kein Auto-Fix**:

1. **Erkennen = abgeleitet.** Aus dem *aktuellen Code* wird gegen die committed Doku geprüft (re-derive +
   diff), nie aus einer handgepflegten Liste. Selbe Heuristik wie das Drift-Gate → konsistent, nicht disziplin-abhängig.
2. **Entscheiden = Mensch.** Pro Drift wählt der Owner die Richtung. Weder Doc noch Code werden automatisch
   geändert — die Maschine schlägt vor, der Mensch entscheidet.
3. **Landen = bestehende Gate-Logik.** Doc-Updates als PR (rückwärts: hier ist die *Doc-Änderung* der Diff),
   Code-Rückbauten als Board-Item für `/flow`. Nichts umgeht den normalen Pfad.

## 3. Ablauf (drei Phasen)

### Phase A — Erkennen (abgeleitet)
- HEAD-SHA festhalten (`git rev-parse HEAD`) — der geprüfte Code-Stand fürs Logbuch.
- `reviewer` im **Audit-Modus** (Bestand, **kein** Diff, **kein** Gate — `agents/reviewer.md` §„Audit-Modus")
  mit dem Zusatz-Fokus **Spec-Drift**: gleicht beobachtbares Verhalten im Code gegen
  `docs/concept.md` + `docs/architecture.md` + `docs/specs/*.md` ab.
- **Drift-Heuristik = identisch zum Drift-Gate** (CONCEPT §4d): neue/geänderte Endpunkte, UI-Flows,
  Ein-/Ausgaben, Fehler-/Statuscodes, Datenfelder, NFR-relevante Limits. Reiner Refactor/Typo ohne
  Verhaltensänderung → **keine** Drift (**Proportionalität**).
- Output = **Drift-Liste**, je Eintrag: `{Bereich, Code-Fundstelle (Pfad:Zeile), betroffene Spec/AC oder „fehlt", Richtungs-Vorschlag}`.

### Phase B — Entscheiden (Mensch, kein Auto-Fix)
Pro Drift genau eine Richtung:

| Richtung | Bedeutung | Folge |
|---|---|---|
| **doc-nachziehen** | Code war beabsichtigt, Doku veraltet | Doc-Update in den Reconcile-PR |
| **code-rückbau** | Verhalten war ungewollt | Board-Item (To Do) → `/flow` |
| **→ requirement** | neue Capability / Scope-Sprung | an `requirement` zur sauberen Spec (Hybrid-Authoring), **nicht** hier nebenbei |
| **akzeptiert (won't-fix)** | bewusst geduldet | nur Logbuch-Eintrag mit Begründung |

### Phase C — Landen
- **Doc-Updates:** **ein** PR auf Branch `reconcile/<datum>`; `concept.md`/`architecture.md`/`specs/*.md`
  nachziehen, `AC<n>`/`BR-NNN` stabil halten bzw. additiv ergänzen. Review durch `reviewer` (gleiche
  Gate-Logik, nur rückwärts). `main` ist protected → **PR, kein Direkt-Push**.
- **Code-Rückbauten:** je Eintrag ein GitHub-Issue (To Do), Acceptance referenziert die nachgezogene Spec/AC.
- **Logbuch:** `docs/spec-audit.md` (anlegen falls fehlend aus `templates/_docs/spec-audit.md`) um einen
  Lauf-Eintrag ergänzen — siehe §4.

## 4. Artefakt — `docs/spec-audit.md` (durable Historie)

Pro Reconcile-Lauf **ein Eintrag**: Datum, geprüfte HEAD-SHA, Drift-Anzahl, Liste mit finalem Status je Drift
(`doc-nachgezogen → PR #`, `rückbau-geplant → Issue #`, `akzeptiert → Begründung`).

**Abgrenzung zur abgeleiteten Map (vgl. `traceability-subsystem.md` §5):** Die **Roh-Drift-Liste** aus Phase A
ist *derived/ephemer* (bei Konflikt gewinnt immer der aus dem Code geparste Ist-Zustand). Das **Logbuch** ist
das Gegenteil — es hält die **getroffenen Entscheidungen** fest (was wann in welche Richtung aufgelöst wurde)
und ist damit durable Audit-Historie, die committet wird. Es wird von `/adopt reconcile` ergänzt, nicht von
Hand gepflegt (Ausnahme: die won't-fix-Begründung).

Liegt im **Ziel-Repo** (`<app>/docs/spec-audit.md`), versioniert neben dem Code — wie der Rest von `docs/`.

## 5. Touchpoints

- **`/adopt`** — hostet den `reconcile`-Modus (`skills/adopt/SKILL.md` §7); reuse der Spec-aus-Code-Maschinerie.
- **`reviewer`** — liefert die Drift-Liste via Audit-Modus (`agents/reviewer.md`); **setzt hier kein Gate**
  (berichtet, gatet nicht — wie beim `/adopt`-Audit). Den Reconcile-**PR** reviewt er dann normal (Phase C).
- **`requirement`** — übernimmt strukturelle Drifts (neue Capability/Scope) zur sauberen Spec (Hybrid-Authoring).
- **`/flow`** — arbeitet die Rückbau-Items ab und landet den Doc-PR durchs Gate.
- **`templates/_docs/spec-audit.md`** — Skelett des Logbuchs.
- **CONCEPT §4d** — definiert die *vorwärtige* Drift-Disziplin; dieses Subsystem ist die *rückwärtige* Aufholung.

## 6. Bewusst NICHT

- **Kein Auto-Fix** — weder Doc noch Code werden automatisch geändert (Phase B ist Mensch-Pflicht).
- **Keine handgepflegte Drift-Matrix als Wahrheit** — Phase A ist immer abgeleitet; durable ist nur die
  Entscheidungs-Historie (§4).
- **Kein eigener reconcile-Agent** (Rolle ≠ Expertise): die Erkennung ist `reviewer`-Audit-Modus, die
  Orchestrierung lebt im `/adopt`-Skill.
- **Kein History-Rewrite, kein Push auf fremdes Upstream** — identisch zu den `/adopt`-Grenzen.
- **Keine Strukturarbeit nebenbei** — neue Capabilities gehen an `requirement`, nicht in den Reconcile-PR.
