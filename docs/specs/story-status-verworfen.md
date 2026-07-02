---
id: story-status-verworfen
title: Story-Status „Verworfen" (Won't-Do/Obsolete) — Enum-Erweiterung + terminale Semantik
status: draft
version: 1
spec_format: use-case-2.0
---

# Spec: Story-Status „Verworfen"  (`story-status-verworfen`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Diese Vorlage ist auf `spec_format: use-case-2.0`** (Frontmatter).
>
> **Bindung.** Der kanonische Story-Status-Enum lebt in [[board-schema]] (§V3/AC3) und im bindenden Detailkonzept `docs/architecture/board-subsystem.md` §4.2/§5. Diese Spec erweitert diesen Enum um den terminalen Wert **„Verworfen"** und nagelt fest, wie die Board-Werkzeuge (`board-lint`, `story.schema.json`, `scripts/board`, `board-github-export`, das `/flow`-Reader-Verhalten, das `reconcile`-Drain-Gate) ihn behandeln.

## Zweck

Einen neuen **terminalen** Story-Status „Verworfen" einführen, der ausdrückt: *diese Story wird bewusst nicht mehr umgesetzt, weil sie nicht mehr gebraucht wird* (Scope gestrichen, durch andere Arbeit überholt). Er grenzt sich klar ab von **Done** (erfolgreich umgesetzt) und **Blocked** (temporär gehindert, soll später weiter). „Verworfen" löst die bisherige informelle Konvention ab, solche Fälle per `[DEFERRED]`-Titelpräfix + Freitext zu markieren.

## Kontext / Designnuancen (bindend)

- **Terminale Menge = {Done, Verworfen}.** Überall, wo das Board-Subsystem heute „Done" als *abgeschlossen/terminal* wertet (Depends-Gate in `board next`, Rollup/Progress, Feature-Vollständigkeit, `reconcile`-Drain-Gate, `/flow`-Auswahl), gilt **Verworfen gleichwertig als terminal** — aber niemals als *erfolgreich*: der „done"-Zähler und `done_at` bleiben ausschließlich dem echten `Done` vorbehalten.
- **Story-only.** „Verworfen" ist ein **Story**-Status. Der Feature-Enum (`Backlog|Planned|Active|Done|Archived`) bleibt **unverändert**.
- **Manuelle/Owner-Entscheidung, kein Loop-Ausgang.** Kein `/flow`-Statusübergang erzeugt „Verworfen" automatisch — es ist eine bewusste Owner- bzw. GUI-Entscheidung (die parallele dev-gui-Schwester-Story liefert Dropdown/Kanban dafür). Die bestehende Single-Writer-Erzwingung für Story-Status (`BOARD_WRITER=flow`) bleibt **unverändert** und gilt gleichermaßen für „Verworfen".
- **Exakter Name = Cross-Repo-Vertrag.** Der Wert lautet in **allen** Artefakten exakt `Verworfen` (deutsch, großes V) — nicht `Discarded`, `Won't Do` oder `verworfen`. Nur so bleibt die parallele dev-gui-Arbeit (Dropdown, Kanban-Spalte, Feature-Status-Ableitung) kompatibel.
- **Minimale Schema-Oberfläche.** Kein neues Feld (kein `discard_reason`). Die Begründung eines Verwurfs lebt im Story-Body/Titel bzw. in der git-Commit-/PR-Historie (git = Audit-Log). `--reason` bleibt optional (anders als bei `Blocked`, das `--reason` erzwingt).

## Main Success Scenario

1. Der Owner (bzw. die dev-gui-GUI) entscheidet, dass eine bestehende Story — typischerweise eine `Blocked`- oder `To Do`-Story — nicht mehr gebraucht wird.
2. Der Status wird auf `Verworfen` gesetzt (`board set <S-###> status Verworfen`, im `BOARD_WRITER=flow`-Kontext).
3. Die Story verschwindet aus der aktiven Arbeit: `board next` greift sie nie auf; das `reconcile`-Drain-Gate zählt sie nicht als offene Spalte; der Feature-Rollup wertet sie als terminal.
4. Ein Dependent, dessen einzige offene Vorbedingung die verworfene Story war, wird durch das Depends-Gate freigegeben (terminale Vorbedingung erfüllt).

## Alternative Flows

### A1: Dependent benötigt die verworfene Arbeit doch
- Wird eine Vorbedingung verworfen, die ein Dependent inhaltlich wirklich braucht, gibt das Depends-Gate den Dependent zwar frei (terminal) — der Owner muss den Dependent dann bewusst nach-bewerten (ebenfalls verwerfen oder neu spezifizieren). Das Board erzwingt hier keine Kaskade.

### E1: Ungültiger Statuswert
- Ein Statuswert außerhalb `{To Do, In Progress, Blocked, In Review, Done, Verworfen}` bleibt ein `ENUM-INVALID`-Fehler (CLI-Abweisung + `board lint`).

## Acceptance-Kriterien

- **AC1** — **Enum-Erweiterung.** `Verworfen` ist ein gültiger Story-Status überall, wo der Story-Status-Enum erzwungen wird: `scripts/board-lint.sh` (`ENUM_STATUS` im Story-Zweig), `board/story.schema.json` (`status.enum`) und die kanonische Enum-Doku ([[board-schema]] §V3/AC3, `docs/architecture/board-subsystem.md` §4.2). Der Feature-Status-Enum bleibt **unverändert**. Der kanonische Story-Enum lautet nach dieser Änderung `To Do | In Progress | Blocked | In Review | Done | Verworfen`.
- **AC2** — **Schreibbarkeit via CLI.** `board set <S-###> status Verworfen` wird vom CLI-Enum-Guard akzeptiert (kein `ENUM-INVALID`-`die`). Die Single-Writer-Erzwingung (`BOARD_WRITER=flow` für Story-Status) bleibt unverändert und greift auch hier. `--reason` ist **optional** (kein Pflicht-`--reason` wie bei `Blocked`). Der Übergang nach `Verworfen` setzt **kein** `done_at` (nur `Done` setzt `done_at`) und löscht ein etwaiges `blocked_reason` (Status ≠ Blocked), konsistent zur bestehenden Set-Logik.
- **AC3** — **Depends-Gate terminal.** In `board next` gilt eine `depends`-Story als erfüllt, wenn ihr Status in der terminalen Menge `{Done, Verworfen}` liegt (bisher nur `Done`). Ein Dependent wird dadurch nicht dauerhaft blockiert, wenn seine Vorbedingung verworfen wurde. *(deckt A1)*
- **AC4** — **Nie als Kandidat.** `board next` wählt **niemals** eine Story mit Status `Verworfen` als nächstes Item (Kandidaten sind ausschließlich `To Do`; `Verworfen` ist ausgeschlossen). Diese AC verankert das als getestete Invariante (Regressionsschutz).
- **AC5** — **Rollup/Progress terminal.** `board rollup` zählt `Verworfen`-Stories als terminal: (a) der `progress`-String weist verworfene Stories separat aus (Suffix `· <N> verworfen`, nur wenn `N > 0`) und mischt sie **nicht** in den `done`-Zähler; der bestehende Präfix `"<done>/<total> done"` bleibt formatstabil (kein Bruch der `ROLLUP-STALE`-Prüfung); (b) die Feature-Vollständigkeit gilt als erreicht, wenn `done + verworfen == total` (terminale Menge `{Done, Verworfen}`) — das ist das Signal, das den Feature-Rollup-Status `Done` vorschlägt (Owner bestätigt, `board-subsystem` §5). Der `done/total`-Zähler behält seine Bedeutung „erfolgreich abgeschlossen / gesamt".
- **AC6** — **`/flow`-Orchestrator terminal + kein Auto-Erzeuger.** `skills/flow/SKILL.md` dokumentiert, dass Stories mit Status `Verworfen` **terminal** sind: vom `/flow`-Loop nicht als offenes To-Do aufgegriffen (folgt aus `board next`) und für Fortschritts-/Rollup-Zwecke wie `Done` gewertet; und dass **kein** `/flow`-Statusübergang `Verworfen` erzeugt (manuelle Owner/GUI-Entscheidung, kein Loop-Ausgang).
- **AC7** — **GitHub-Export Round-Trip.** `scripts/board-github-export` bildet eine GitHub-Status-Spalte `Verworfen` in seiner `STATUS_MAP` verlustfrei auf den internen Status `Verworfen` ab (inkl. Kleinschreib-Variante `verworfen`). Ein Board mit dieser Spalte importiert ohne Fallback-Verlust; unbekannte Status fallen weiterhin auf `To Do` (WARN).
- **AC8** — **Reconcile-Drain-Gate.** Das Stufe-2-Drain-Gate (`scripts/reconcile-stage2-gate.sh`) betrachtet ausschließlich die vier **aktiven** Spalten (`To Do, In Progress, Blocked, In Review`). `Verworfen` ist — wie `Done` — **keine** aktive Spalte und blockiert das Drain-Gate nicht (eine verworfene Story gilt als geleert/terminal). Diese AC verankert das als getestete Invariante + einen Kommentar, der `Verworfen` neben `Done` als terminal/nicht-aktiv benennt. *(keine Logik-Änderung nötig — Regressionsschutz)*
- **AC9** — **Migration.** Bestehende, informell per `[DEFERRED]`-Titelpräfix markierte Stories werden **nicht** automatisch/massenhaft umgeschrieben. Der neue Status gilt nur für künftige Fälle; eine Migration ist optional und manuell. Es wird **kein** Migrationsskript eingeführt.
- **AC10** — **Naming-Vertrag (Cross-Repo).** Der Statuswert lautet in **allen** Artefakten exakt `Verworfen` (deutsch, großes V) — nicht `Discarded`/`Won't Do`/`verworfen`. Damit bleibt die parallele dev-gui-Schwester-Story (Dropdown/Kanban-Spalte/Feature-Status-Ableitung) kompatibel.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace story-status-verworfen#AC<n>` gemäß `knowledge/<lang>.md` → `## Spec-Tagging`. Da `language: md` (No-Op-Build), sind die „Tests" hier die mechanischen Board-Tooling-Smokes (`board set`/`next`/`rollup`/`lint` gegen Fixtures) bzw. Doku-Diffs (`SKIPPED-DOC-ONLY`).

## Verträge

### Story-Status-Enum (nach dieser Änderung)
```
To Do | In Progress | Blocked | In Review | Done | Verworfen
```
Terminale Menge (abgeschlossen/nicht-aktiv): `{ Done, Verworfen }`.
Erfolgreich-abgeschlossen (setzt `done_at`, zählt in `done/total`): **nur** `Done`.

### `board next` — Depends-Gate
```
Eine depends-Story erfüllt das Gate, wenn status ∈ {Done, Verworfen}.
Kandidatenmenge = Stories mit status == "To Do" (Verworfen nie enthalten).
```

### `board rollup` — Progress-Format
```
"<done>/<total> done [· <N> in progress] [· <N> in review] [· <N> blocked] [· <N> verworfen]"
```
`done` = #`Done`; `total` = #Kind-Stories (inkl. verworfener); `verworfen`-Suffix nur wenn `N > 0`.
Feature-Vollständigkeit (Rollup schlägt Feature-`Done` vor): `#Done + #Verworfen == total`.

### `board-github-export` — STATUS_MAP-Ergänzung
```
"Verworfen": "Verworfen",
"verworfen": "Verworfen",
```

## Edge-Cases & Fehlerverhalten

- **Dependent einer verworfenen Story** → Depends-Gate erfüllt (terminal); Owner bewertet den Dependent bewusst nach (A1). Keine automatische Kaskade.
- **Feature mit gemischten Kind-Status** (z. B. 1× Done, 2× Verworfen) → `progress` = `1/3 done · 2 verworfen`; Feature-Vollständigkeit erreicht (`1 + 2 == 3`).
- **Übergang nach `Verworfen`** → `done_at` bleibt `null`; ein gesetztes `blocked_reason` wird gelöscht (Status ≠ Blocked), konsistent zur bestehenden Set-Logik.
- **Ungültiger Statuswert** → `ENUM-INVALID` (CLI-`die` + `board lint`), unverändert.
- **`board lint` gegen eine `Verworfen`-Story** → kein Fehler (Wert ist jetzt im Enum); `ROLLUP-STALE`-Prüfung bleibt grün, da der `done/total`-Präfix formatstabil ist.

## NFRs

- **Determinismus:** `board lint`/`next`/`rollup` bleiben rein mechanisch, reproduzierbar (keine LLM-Runde).
- **Rückwärtskompatibilität:** additive Enum-Erweiterung; das Progress-Format wird nur um ein optionales Suffix erweitert (bestehende Konsumenten wie [[dev-gui-board-aggregator]], die `status`/`progress` durchreichen, brechen nicht).
- **Minimale Oberfläche:** keine neuen Felder, kein Migrationsskript.

## Nicht-Ziele

- **dev-gui-GUI** (Status-Dropdown, Kanban-Spalte „Verworfen", Feature-Status-Ableitung) — das ist die **parallele Schwester-Story im dev-gui-Repo**; hier nur der Schema-/Backend-Vertrag, auf dem sie aufsetzt (exakter Name „Verworfen" ist der Kompatibilitätsvertrag, AC10).
- **Automatische `[DEFERRED]`-Migration** (AC9) — kein Massen-Umschreiben.
- **Eigenes `discard_reason`-Feld** — bewusst nicht eingeführt (Begründung via Body/Commit).
- **Relaxierung der Single-Writer-Erzwingung** (`BOARD_WRITER=flow`) — bleibt unverändert. **Koordinationshinweis:** falls die dev-gui-GUI Story-Status direkt setzen muss, geschieht das in ihrem Flow-Writer-Kontext (setzt `BOARD_WRITER=flow`) bzw. wird dort separat entschieden — nicht in dieser Spec.

## Abhängigkeiten

- [[board-schema]] §V3/AC3 — kanonischer Story-Status-Enum (wird um `Verworfen` fortgeschrieben).
- `docs/architecture/board-subsystem.md` §4.2, §5, §7 — bindendes Detailkonzept (Story-Lebenszyklus + terminale Wertung).
- [[board-cli]] — implementiert `set`/`next`/`rollup` gegen diese Regeln.
- [[board-github-export]] — STATUS_MAP-Round-Trip (AC7).
- [[reconcile]] — Stufe-2-Drain-Gate (AC8).
- [[flow-board-backend]] / `skills/flow/SKILL.md` — `/flow`-Reader-Verhalten (AC6).
- [[dev-gui-board-aggregator]] — Konsument (reicht `status`/`progress` durch; Naming-Vertrag AC10).
