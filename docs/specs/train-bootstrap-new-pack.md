---
id: train-bootstrap-new-pack
title: train --bootstrap — neuen Knowledge-Pack ohne Vorgänger aus mitgegebenen Primärquellen anlegen
status: draft
version: 1
---

# Spec: Neuen Pack via `--bootstrap` anlegen  (`train-bootstrap-new-pack`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die ACs), `reviewer` (Drift-Gate).

## Zweck

`/train --bootstrap <pack-id>` legt heute einen **fehlenden** Pack an — aber **Cut-orientiert**: das Skelett entsteht durch Kopie eines **Vorgänger-Packs** (neuer Framework-/Tool-Major), und die Quellen werden vom Vorgänger geerbt. Für ein **brandneues** Knowledge-Thema **ohne Vorgänger** (neue Sprache, neue Framework-Familie, neues Build-/Migration-Tool) fehlt der Weg. Diese Spec ergänzt `--bootstrap` so, dass ein **neuer Pack from-scratch** angelegt werden kann, dessen **Primärquellen als Argument mitgegeben** werden. Das ist der agent-flow-seitige Enabler für „Knowledge hinzufügen" aus der GUI ([[../specs/team-knowledge-add]] in dev-gui).

## Kontext / Designentscheidungen (bindend)

- **Owner-Entscheidung 2026-06-19:** „Knowledge hinzufügen" = **Thema benennen + autoritative Quellen mitgeben**, der Train **recherchiert** daraus und baut den Pack. **Kein** mitgegebener Eigen-Inhalt (separate Variante, hier Nicht-Ziel).
- **Additiv & rückwärtskompatibel.** Der bestehende Cut-Bootstrap (Vorgänger-Kopie) bleibt unverändert. Neu ist nur der **No-Predecessor**-Fall + **Quellen-als-Argument**.
- **Quellen sind Pflicht beim From-Scratch-Pack.** Ohne Vorgänger gibt es nichts zu erben — der Pack braucht ≥1 autoritative `primary_source`, sonst kann der Train keine Regel belegen (Train promotet nur aus Primärquellen). Fehlen Quellen → **STOPP** mit klarer Meldung.
- **PR + Gate unverändert.** Der neue Pack geht als PR (Branch `bootstrap/<pack-id>`) + `reviewer`-Check + **Mensch-Approve** in den Knowledge Space. Nichts wird auto-/self-gemergt. Das ist die Sicherheits-/Qualitätsgrenze gegen ungeprüfte oder schlecht belegte Packs.
- **Quellen-Disziplin hart.** Nur die mitgegebenen `primary_sources` werden zitiert; `non_sources`-Defaults (dev.to, medium, stackoverflow, geeksforgeeks) werden gesetzt und respektiert. Preview/experimental ≠ stable.

## Verhalten

### V1 — Aufruf-Form mit Quellen-Argument
`/train --bootstrap <pack-id> [<source-url> …]` — eine oder mehrere autoritative Quell-URLs (leerzeichengetrennt, je URL ohne Leerzeichen). Die URLs werden als `primary_sources` des neuen Packs übernommen und sind die Recherche-Basis.

### V2 — Pack-Typ & Ablageort aus der Pack-ID
Der Ablageort/das Format ergibt sich aus der Pack-ID über den bestehenden Resolver (`framework-build-subsystem.md §8`):
- **Sprache** (`<id>`, kein Unterordner) → `knowledge/<id>.md`, **ohne** YAML-Frontmatter, Form `# Knowledge Pack: <id>`, Regel-IDs `<id>/R<NN>` (analog `ts.md`/`js.md`).
- **Framework** (`<id>@<major>`) → `knowledge/frameworks/<id>-<major>.md`, **mit** Frontmatter (`pack`, `pack_version: 1.0`, `framework_version_range`, `pack_date`, `primary_sources`, `non_sources`), Regel-IDs `<pack>/A<NN>`.
- **Build/Migration** (`build/<id>`, `migration/<id>[@<major>]`) → analog Framework-Format im jeweiligen Ordner.

### V3 — No-Predecessor-Skelett
Existiert **kein** Vorgänger-Pack, wird das Skelett **frisch** erzeugt (statt Kopie):
- Header wie in V2 (Quellen aus V1, `pack_date` = heute, `pack_version: 1.0`), kein `superseded_by`.
- Für Framework/Build: Sektion **A leer→befüllt**, **B leer** (retro-Hoheit), **C** als Floor-Grundgerüst (Default-Inhalt, da kein Vorgänger zum Erben).
- Für Sprach-Packs: die etablierte Sektionsstruktur (Coder-Guidance) frisch anlegen.

### V4 — Sektion A / Regeln aus den Quellen befüllen
Wie im Normal-Lauf, aber: die **3-Regel-Obergrenze ist gelockert** (initiale Befüllung darf den Stable-Stand abbilden). Jede Regel mit **Quell-Link** (aus den mitgegebenen `primary_sources`) + stabiler ID. Quellen-Disziplin bleibt hart.

### V5 — Kollisions-Schutz
Existiert der Pack **bereits** → **kein** Bootstrap-Add: STOPP mit Hinweis „Pack `<id>` existiert — nutze `/train <id>` zum Aktualisieren". (Verhindert versehentliches Überschreiben.)

### V6 — Lieferung & Gate
Wie Cut-Bootstrap: PR auf Branch `bootstrap/<pack-id>` + `LEARNINGS.md`-Zeile (`Proposed`) + `reviewer`-Check + **Mensch-Approve**. Bei gesetztem `AGENT_FLOW_KNOWLEDGE_DIR` zusätzlich ins Staging-Dir (für autonome `/upgrade`-Läufe, unverändert). Kein Auto-/Self-Merge.

## Acceptance-Kriterien

- **AC1** — `/train --bootstrap <pack-id> <url> [<url> …]` übernimmt die URLs als `primary_sources` des neuen Packs und nutzt sie als Recherche-Basis. *(V1)*
- **AC2** — Der Ablageort/das Pack-Format wird korrekt aus der Pack-ID abgeleitet (Sprache ohne Frontmatter / Framework·Build·Migration mit Frontmatter), inkl. passender Regel-ID-Schemata. *(V2)*
- **AC3** — Existiert kein Vorgänger, wird ein frisches Skelett erzeugt (kein Kopier-Fehler/Abbruch); Header mit heutigem `pack_date`, `pack_version: 1.0`, ohne `superseded_by`. *(V3)*
- **AC4** — Sektion A / Regeln werden aus den mitgegebenen Primärquellen befüllt (3-Regel-Cap gelockert, jede Regel mit Quell-Link + ID); nur `primary_sources` zitiert, `non_sources` gesetzt. *(V4)*
- **AC5** — Fehlt beim From-Scratch-Pack jede Quelle → STOPP mit klarer Meldung (kein leeres/unbelegtes Pack). *(Kontext)*
- **AC6** — Existiert der Pack bereits → STOPP mit Hinweis auf `/train <id>` (kein Überschreiben). *(V5)*
- **AC7** — Lieferung als PR (Branch `bootstrap/<pack-id>`) + Gate (reviewer + Mensch-Approve); kein Auto-/Self-Merge; Cut-Bootstrap-Verhalten unverändert. *(V6)*

## Verträge

- **Eingabe:** `/train --bootstrap <pack-id> [<source-url> …]` (Skill `skills/train/SKILL.md`).
- **Resolver:** Pack-ID → Ablageort/Format (`docs/architecture/framework-build-subsystem.md §8`).
- **Ausgabe:** neuer Pack-File im korrekten Ordner/Format, PR gegen `Studis-Softwareschmiede/agent-flow`, `LEARNINGS.md`-Zeile.

## Edge-Cases & Fehlerverhalten

- **Keine URL** → STOPP (AC5).
- **Pack existiert** → STOPP + Hinweis auf Train (AC6).
- **Ungültige/unerreichbare URL** → der Train behandelt nicht abrufbare Quellen wie im Normal-Lauf (Spot-Check/Klärung); ist gar keine Quelle verwertbar → Pack mit Skelett + Hinweis, keine unbelegten Regeln.
- **Mehrdeutige Pack-ID** → bestehendes Ambiguitäts-Stopp (Optionsliste), unverändert.

## NFRs

- **Quellen-Disziplin:** nur mitgegebene `primary_sources`; `non_sources`-Defaults; Preview ≠ stable.
- **Gate = Sicherheitsgrenze:** neuer Pack nur nach Mensch-Approve im Knowledge Space.

## Nicht-Ziele

- **Mitgegebener Eigen-Inhalt** (eigene Regeln/Doku als Seed) — nicht gewählt; bräuchte einen Nebenkanal (separate Variante).
- **Auto-Merge / Self-Merge** neuer Packs.
- **Änderung des Cut-Bootstrap** (Vorgänger-Kopie bleibt).
- **GUI-Anteil** — separat ([[../specs/team-knowledge-add]] in dev-gui).

## Abhängigkeiten

- **agent-flow:** `skills/train/SKILL.md` (Bootstrap-Parsing + Quellen-Argument), `agents/train.md` (Abschnitt „Bootstrap-Modus" — No-Predecessor-Fall), Pack-ID-Resolver (`docs/architecture/framework-build-subsystem.md §8`), `knowledge/_meta/versioning.md`.
- **Cross-Repo (Konsument):** dev-gui `team-knowledge-add` — feuert `--bootstrap` mit Name + Quellen.
