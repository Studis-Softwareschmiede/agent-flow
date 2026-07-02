---
id: board-cli
title: Board-Abstraktion (scripts/board) — Verben, Queue-Logik, Single-Writer
status: active
version: 1
---

# Spec: Board-CLI  (`board-cli`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Board-Subsystem ist in `docs/architecture/board-subsystem.md` spezifiziert (bindend, §7). Diese Spec definiert `scripts/board` als die **einzige** Stelle, die das Board-Dateiformat ([[board-schema]]) kennt: die Verben aus §7, die Queue-Logik von `board next` und die Single-Writer-Regel. Agents rufen nur Verben — der Backend-Wechsel bleibt eine lokale Änderung.

## Zweck

Eine dünne, deterministische CLI (`scripts/board`), die das Board-Dateiformat kapselt. Sie liest/schreibt Feature- und Story-YAML, vergibt kollisionsfreie IDs, liefert mit `board next` die nächste bereite Story für `/flow` und prüft Integrität mit `board lint`. Sie ist der einzige Ort, der das Format kennt — alle Agents (requirement liest/legt an, flow liest/schreibt Status, coder/reviewer/tester lesen) gehen ausschliesslich über sie.

## Kontext / Designnuancen (bindend)

- **Einzige Format-kennende Stelle.** Kein Agent parst Board-YAML direkt; alles läuft über die Verben (board-subsystem §7). Das macht den Big-Bang-Cut zur lokalen Änderung.
- **Single-Writer für Status.** Nur `/flow` darf `board set <story> status …` aufrufen. `requirement` darf `feature add`/`story add` und nicht-Status-Felder setzen, NICHT den Story-Status (§7). Das CLI erzwingt die Regel über einen Aufrufer-Marker (s. V8).
- **Deterministische Queue.** `board next` ist reproduzierbar: gleiche Board-Dateien → gleiche nächste Story (§7).
- **`lint` delegiert an Schema.** Die Integritätsregeln selbst sind in [[board-schema]] V5–V11 definiert; `board lint` ist deren ausführende Umsetzung.
- **JSON-Ausgabe maschinenlesbar.** `next`/`show`/`list` geben JSON für Agents aus; `set`/`add` geben die neue/geänderte ID aus.
- **ID-Vergabe atomar.** `feature add`/`story add` ziehen die nächste Nummer aus `board.yaml`, erhöhen den Zähler und schreiben Datei + `board.yaml` konsistent ([[board-schema]] V1).
- Konservative Annahme: `board export-github` ist hier nur als Verb-Stub registriert; das eigentliche Migrations-Verhalten spezifiziert [[board-github-export]].

## Verhalten

### V1 — `board feature add`
`board feature add --title … --goal … --priority P<n> [--spec …] [--labels …] [--depends …]` legt `board/features/F-###-<slug>.yaml` an: zieht die nächste `F-`-Nummer aus `board.yaml`, erhöht `next_feature_id`, setzt `status=Backlog`, `created_at`/`updated_at`, und gibt die neue `F-###` aus. Slug wird aus `--title` abgeleitet.

### V2 — `board story add`
`board story add --parent F-### --title … --spec … --implements AC1,AC2 [--priority P<n>] [--depends …] [--labels …]` legt `board/stories/S-###-<slug>.yaml` an: zieht die nächste `S-`-Nummer, erhöht `next_story_id`, setzt `status=To Do`, `created_at`/`updated_at`, gibt die neue `S-###` aus. `--parent` muss existieren (sonst Fehler, kein Schreiben). Default `--priority P2`.

### V3 — `board set`
`board set <id> <feld> <wert> [--reason …]` setzt ein einzelnes Feld eines Features/Story und aktualisiert `updated_at`. Der Sonderfall `board set <story-id> status <wert>` ist statusschreibend und unterliegt der Single-Writer-Regel (V8). Bei `status=Blocked` ist `--reason` erforderlich und wird nach `blocked_reason` geschrieben; bei `status=Done` wird `done_at` gesetzt.

### V4 — `board show`
`board show <id>` gibt ein Feature oder eine Story als JSON aus (alle Felder), inklusive abgeleiteter Felder bei Features. Unbekannte ID → Fehler, Exit ≠ 0.

### V5 — `board list`
`board list [--type feature|story] [--status …] [--parent F-###]` gibt die gefilterte Liste als JSON-Array aus, sortiert nach `priority` dann `id`. Ohne Filter: alle Items.

### V6 — `board next` (Queue-Logik)
`board next` liefert die **erste Story mit `status=To Do`, deren `depends` alle `status=Done` sind**, sortiert nach: Story-`priority` (P0 zuerst), Tie-Break Parent-Feature-`priority`, dann `id` aufsteigend (board-subsystem §7). Ausgabe als JSON: mindestens `id`, `spec`, `implements`, `parent`, `priority`, `labels`; zusätzlich die Kontext-Felder `title`, `status` und `depends` für `/flow`. Keine bereite Story → leere/`null`-Ausgabe, Exit 0 (kein Fehler). Stories mit ungelösten `depends` werden übersprungen, nicht zurückgegeben. Fehlt `board.yaml` oder das Stories-Verzeichnis → leere Ausgabe, Exit 0 (kein Fehler; `/flow` interpretiert das als „nichts zu tun").

### V7 — `board rollup`
`board rollup <F-###>` berechnet `stories[]` und `progress` des Features aus den Kind-Stories neu und schreibt sie ([[board-schema]] V10). Optional `board rollup --all` über alle Features. Es ist die einzige Quelle für `progress`/`Active`/`Done`-Vorschlag (§11).

### V8 — `board lint`
`board lint` führt die Integritätsregeln aus [[board-schema]] V5–V11 aus (parent existiert, depends auflösbar/azyklisch, AC in Spec, IDs eindeutig, Pflichtfelder/Enums, Rollup-Konsistenz als Warnung), gibt je Verstoss `FEHLER|WARN <regel-id> <datei> <detail>` aus und endet Exit ≠ 0 nur bei ≥1 Fehler.

### V9 — Single-Writer-Erzwingung
`board set <story-id> status …` ist nur aus dem `/flow`-Kontext erlaubt (Aufrufer-Marker, z.B. Env-Variable/Flag, die nur `/flow` setzt). Ein anderer Aufrufer → Fehler „nur /flow darf Story-Status setzen", kein Schreiben, Exit ≠ 0. Nicht-Status-Felder (`board set <id> <anderes-feld> …`) sind für `requirement` und andere erlaubt.

### V10 — Determinismus & Atomarität
Alle lesenden Verben sind ohne LLM und deterministisch. Schreibende Verben (`add`/`set`/`rollup`) schreiben Datei + ggf. `board.yaml` atomar (kein halber Zustand bei Fehler); bei ungültiger Eingabe wird NICHTS geschrieben und Exit ≠ 0 zurückgegeben.

### V11 — `board export-github` (Verb-Registrierung)
`board export-github` ist als Verb registriert und delegiert an das Migrations-Verhalten aus [[board-github-export]]. Diese Spec garantiert nur die Existenz/Hilfe des Verbs; das Verhalten ist dort spezifiziert.

### V12 — `board ready` (Readiness-Gate)
`board ready [--quiet]` prüft je To-Do-Story, ob sie für autonome Abarbeitung bereit ist. Alle folgenden Regeln müssen erfüllt sein:

- **R1:** `status == "To Do"` — nur To-Do-Items werden bewertet; alle anderen Status werden als `(n/a)` übersprungen.
- **R2:** `spec` ist gesetzt **und** die referenzierte Datei existiert **und** ihr YAML-Frontmatter enthält `status: active`.
- **R3:** `implements` ist nicht leer **und** jede gelistete AC-Nummer kommt in der Spec-Datei vor.
- **R4:** `depends` ist leer/null **oder** alle referenzierten Stories haben `status == "Done"`.
- **R5:** `blocked_reason` ist leer/null.

Nicht maschinell prüfbar (kein Fehlkriterium): „AC testbar formuliert", „keine offene Owner-Frage".

**Ausgabe** je Story:
```
READY     S-xxx
NOT-READY S-xxx — <konkreter Grund je verletzter Regel>
(n/a)     S-xxx      (status != "To Do"; nur ohne --quiet)
```
Plus eine Summary-Zeile am Ende: `Summary: <n>/<total> To-Do-Stories ready`.

**Aggregierter NOT-READY-Diagnose-Block** ([[empty-drain-diagnostics]] AC1/AC2): Nach den `READY`/`NOT-READY`-Einzelzeilen und vor der Summary gibt `board ready` — **nur wenn ≥1 To-Do-Story `NOT-READY` ist** — einen nach Grund-Kategorie gruppierten Aggregat-Block aus. Feste, deterministische Kategorien-Reihenfolge; jede Kategorie nur, wenn ≥1 Story betroffen ist. Stabiles Zeilen-Präfix `WAITING <kategorie> (<n>): S-xxx, S-yyy`:

```
WAITING spec-not-active (12): S-003, S-004, … — Specs: docs/specs/a.md, docs/specs/b.md
WAITING spec-missing (1): S-007
WAITING ac-missing (2): S-010, S-011
WAITING depends-open (2): S-012, S-013
WAITING blocked (1): S-020
```

Kategorien (feste Reihenfolge): `spec-not-active` (R2: Spec-Frontmatter `status != active` bzw. kein Frontmatter/unlesbar) — nennt **zusätzlich** die betroffenen Spec-Pfade (`— Specs: …`, dedupliziert + sortiert); `spec-missing` (R2: `spec` nicht gesetzt / Spec-Datei fehlt); `ac-missing` (R3: `implements` leer / AC fehlt in Spec / ungültiger Typ); `depends-open` (R4); `blocked` (R5). Story-IDs je Kategorie aufsteigend sortiert. Eine Story mit mehreren Blockern erscheint in **jeder** zutreffenden Kategorie (Gründe sind nicht exklusiv). Der Block ist token-frei/deterministisch (reines `python3` im CLI) und ändert den Exit-Code-Vertrag nicht. Bei ausschließlich readyen oder keinen To-Do-Stories entfällt der Block.

**`--quiet`:** unterdrückt `(n/a)`-Zeilen; gibt weiterhin `READY`/`NOT-READY`, den Aggregat-Block und die Summary aus.

**Exit-Code:** 0 wenn alle To-Do-Items ready sind (oder keine To-Do-Items vorhanden sind); 1 wenn mindestens eine To-Do-Story `NOT-READY` ist. Damit verwendbar als Gate vor einem autonomen `/flow`-Lauf.

**Robustheit:** fehlende/kaputte Felder → Story gilt als `NOT-READY` mit konkretem Grund; kein Abbruch des Gesamtlaufs. Fehlt `board.yaml` oder das Stories-Verzeichnis → Exit 0 (keine To-Do-Items).

## Acceptance-Kriterien

- **AC1** — `board feature add` legt eine Feature-YAML an, zieht die nächste `F-`-Nummer aus `board.yaml`, erhöht `next_feature_id`, setzt `status=Backlog`+Zeitstempel und gibt die neue `F-###` aus. *(V1)*
- **AC2** — `board story add` verlangt ein existierendes `--parent`, legt eine Story-YAML mit `status=To Do`+Zeitstempel an, zieht die nächste `S-`-Nummer, erhöht `next_story_id`, gibt die `S-###` aus; unbekanntes Parent → kein Schreiben, Exit ≠ 0. *(V2)*
- **AC3** — `board set <id> <feld> <wert>` setzt das Feld + `updated_at`; `status=Blocked` erfordert `--reason`→`blocked_reason`, `status=Done` setzt `done_at`. *(V3)*
- **AC4** — `board show <id>` gibt das Item als JSON inkl. abgeleiteter Felder aus; unbekannte ID → Exit ≠ 0. *(V4)*
- **AC5** — `board list` filtert nach `--type`/`--status`/`--parent` und gibt ein nach `priority,id` sortiertes JSON-Array aus. *(V5)*
- **AC6** — `board next` liefert die erste `To Do`-Story mit vollständig erfüllten `depends`, sortiert Story-priority → Feature-priority → id; Stories mit offenen `depends` werden übersprungen; keine bereite Story oder fehlendes Board → leere Ausgabe, Exit 0. JSON-Ausgabe enthält mindestens `id`, `spec`, `implements`, `parent`, `priority`, `labels` sowie die Kontext-Felder `title`, `status`, `depends` für `/flow`. *(V6)*
- **AC7** — `board rollup <F-###>` berechnet `stories[]`/`progress` aus den Kind-Stories neu und schreibt sie; `--all` über alle Features. *(V7)*
- **AC8** — `board lint` führt die Schema-Regeln aus und endet Exit ≠ 0 nur bei ≥1 Fehler (Warnungen allein → Exit 0). *(V8, [[board-schema]] V11)*
- **AC9** — `board set <story> status …` ist nur aus dem `/flow`-Kontext erlaubt; ein anderer Aufrufer → kein Schreiben, Fehlermeldung, Exit ≠ 0; nicht-Status-Felder bleiben für `requirement` erlaubt. *(V9)*
- **AC10** — Lesende Verben sind deterministisch ohne LLM; schreibende Verben sind atomar (kein halber Zustand) und schreiben bei ungültiger Eingabe nichts (Exit ≠ 0). *(V10)*
- **AC11** — `board export-github` ist als Verb registriert und delegiert an [[board-github-export]]; das Verb existiert und liefert Hilfe. *(V11)*
- **AC12** — `board ready` listet je To-Do-Story `READY S-xxx` oder `NOT-READY S-xxx — <Grund>` (Regeln R1–R5), gibt einen aggregierten NOT-READY-Diagnose-Block (gruppiert nach Grund-Kategorie mit stabilem `WAITING <kategorie> (<n>): …`-Präfix; nur bei ≥1 NOT-READY; `spec-not-active` nennt zusätzlich die Spec-Pfade — [[empty-drain-diagnostics]] AC1/AC2) sowie eine Summary aus und endet mit Exit 0 wenn alle To-Do-Items ready (oder keine vorhanden), Exit 1 wenn ≥1 NOT-READY. `--quiet` unterdrückt n/a-Zeilen. Fehlende/kaputte Felder → NOT-READY mit Grund, kein Crash. *(V12)*

## Verträge

### Verb-Übersicht (board-subsystem §7)
```
board next                                          → JSON (id, spec, implements, parent, priority, labels, title, status, depends) | null
board show <id>                                     → JSON (Feature|Story, alle Felder)
board feature add --title --goal --priority [...]   → F-###
board story   add --parent --title --spec --implements [...] → S-###
board set <id> status <wert> [--reason …]           # NUR /flow (V9)
board set <id> <feld> <wert>
board list [--type feature|story] [--status …] [--parent F-###]   → JSON-Array
board rollup <F-###> | --all
board lint                                          → FEHLER|WARN-Zeilen, Exit-Code
board ready [--quiet]                               → READY|NOT-READY-Zeilen + Summary, Exit-Code
board export-github                                 → siehe [[board-github-export]]
```

### Queue-Auswahl (`board next`, exakt)
1. Kandidaten = alle Stories mit `status == "To Do"`.
2. Filter: alle `depends`-Stories haben `status == "Done"` (offene depends → raus).
3. Sortierung: `priority` (P0<P1<P2<P3) → Parent-Feature-`priority` → `id` aufsteigend.
4. Ergebnis = erstes Element, sonst `null`.

## Edge-Cases & Fehlerverhalten

- **`board.yaml` fehlt** (Board nicht initialisiert) → schreibende Verben Fehler „Board nicht initialisiert"; `board lint` meldet es. Lesende Verben (`next`, `list`, `show`) liefern leere Ausgabe/Exit 0 bzw. „nicht gefunden"-Fehler; insbesondere `board next` ohne Board → leere Ausgabe, Exit 0.
- **`board next` ohne bereite Story** → `null`/leer, Exit 0 (kein Fehler; `/flow` interpretiert das als „nichts zu tun").
- **Zyklische `depends`** → `board next` kann eine Story nie liefern (alle blockieren sich); `board lint` deckt den Zyklus als Fehler auf ([[board-schema]] V7).
- **`set status` auf nicht-existente ID** → Exit ≠ 0, kein Schreiben.
- **Paralleler ID-Zugriff** (zwei Branches) → Zähler in `board.yaml`; Doppel-ID wird erst beim Merge sichtbar und von `board lint` erkannt (§11).
- **`set` auf abgeleitetes Feld** (`stories`/`progress`) → abgelehnt (nur über `rollup` pflegbar).

## NFRs

- **Token-frei:** alle Verben deterministisch, ohne LLM (board-subsystem §7).
- **Kapselung:** kein anderer Agent/Skript parst Board-YAML direkt — nur über `board`.
- **Performance:** `next`/`list` skalieren linear mit Item-Zahl; Re-Scan bei jedem Aufruf akzeptabel (kein Daemon nötig in v1).

## Nicht-Ziele

- Dateiformat/Feld-Definition + Lint-Regel-Semantik selbst ([[board-schema]]).
- Skelett-Anlage beim Projektstart ([[new-project-board]]).
- `/flow`-Integration der Verben ([[flow-board-backend]]).
- Migration aus GitHub ([[board-github-export]]).
- dev-gui-Aggregation ([[dev-gui-board-aggregator]]).

## Abhängigkeiten

- [[board-schema]] — Dateiformat + Lint-Regeln, die dieses CLI ausführt.
- `docs/architecture/board-subsystem.md` §7, §8, §11 — bindendes Detailkonzept.
- [[board-github-export]] — Verhalten hinter `board export-github`.
- [[empty-drain-diagnostics]] — aggregierter NOT-READY-Diagnose-Block der `board ready`-Ausgabe (V12/AC12).
