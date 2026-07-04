---
id: new-project-board
title: Projekt-Bootstrap mit File-Board — board/-Skelett statt gh project create
status: active
version: 1
---

# Spec: Projekt-Bootstrap mit File-Board  (`new-project-board`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Board-Subsystem ist in `docs/architecture/board-subsystem.md` spezifiziert (bindend, §6, §8). Diese Spec ersetzt im Projekt-Bootstrap (`new-project`, analog `adopt`) das `gh project create` durch das Anlegen eines `board/`-Skeletts und setzt im Profil `board: file` statt einer GitHub-Projekt-Nummer.

## Zweck

Beim Anlegen eines neuen Projekts entsteht das Board nicht mehr als GitHub Project v2, sondern als git-versioniertes `board/`-Skelett im Repo (`board.yaml` + leere `features/`/`stories/`-Ordner), und das Profil markiert das File-Backend mit `board: file`. So trägt jedes Repo sein Board ab dem ersten Commit bei sich.

## Kontext / Designnuancen (bindend)

- **board/-Skelett statt `gh project create`.** `new-project` legt `board/board.yaml` + `board/features/` + `board/stories/` an (board-subsystem §8). Kein `gh project create`, kein PAT, keine Board-Nummer.
- **`board: file` im Profil.** Das bisherige `board: <nummer>`-Feld in `.claude/profile.md` wird zu `board: file` (Backend-Marker, §6/§8).
- **Initiale `board.yaml`.** `schema_version`, `project_slug` (aus Projektname), Zähler auf Startwert (nächste freie Nummer = 1 → `F-001`/`S-001`). Konform zu [[board-schema]] V1.
- **CLI legt an, nicht der Skill direkt.** Wo möglich nutzt der Bootstrap die `board`-CLI ([[board-cli]]) für die Skelett-Anlage statt eigenes YAML zu schreiben (eine format-kennende Stelle). Konservative Annahme: ein Verb `board init` (oder das schreibende Anlegen der `board.yaml` durch `feature/story add` beim ersten Aufruf) deckt das ab; falls nicht vorhanden, schreibt der Bootstrap das minimale `board.yaml`-Skelett konform zu [[board-schema]].
- **Leeres Board ist gültig.** Ein frisch gebootstrapptes Board (kein Feature/keine Story) muss `board lint`-grün sein ([[board-schema]] Edge-Case).
- **`adopt`-Parallele.** `adopt` legt dasselbe Skelett an und hängt Funde als Stories unter ein Auto-Feature „Adoption-Backlog" (board-subsystem §8) — hier nur als Anschluss benannt; die Adopt-Funde selbst sind ausserhalb dieser Spec.

## Verhalten

### V1 — board/-Skelett anlegen
`new-project` erstellt im neuen Repo `board/board.yaml`, `board/features/` und `board/stories/`. Die Ordner existieren auch leer (z.B. `.gitkeep`), damit sie committet werden.

### V2 — initiale board.yaml
`board/board.yaml` wird mit `schema_version`, `project_slug` (aus dem Projektnamen abgeleitet) und Start-Zählern (`next_feature_id`, `next_story_id` so, dass die erste Vergabe `F-001`/`S-001` ergibt) angelegt — konform zu [[board-schema]] V1.

### V3 — Profil-Marker
`.claude/profile.md` wird mit `board: file` angelegt (statt `board: <nummer>`). Falls ein bestehender Bootstrap-Pfad eine Board-Nummer setzte, entfällt dieser Schritt ersatzlos.

### V4 — kein gh-Board
Der Bootstrap-Pfad ruft KEIN `gh project create` mehr auf und legt keine GitHub-Projekt-Nummer an. Es gibt keinen Restpfad, der noch eine Nummer erwartet.

### V5 — lint-grünes Leer-Board
Direkt nach dem Bootstrap (ohne Features/Stories) ist `board lint` grün (Exit 0) — das leere Skelett ist ein gültiger Board-Zustand.

### V6 — Skelett über die CLI
Die Skelett-Anlage geht — wo verfügbar — über die `board`-CLI ([[board-cli]]), so dass der Bootstrap das Dateiformat nicht selbst kennt. Ist kein Init-Verb vorhanden, schreibt der Bootstrap ein minimales `board.yaml` strikt nach [[board-schema]] V1.

### V7 — Doku-Anschluss
Die Bootstrap-Doku/Templates (z.B. `templates/`, `new-project`-Skill) beschreiben das File-Board als Standard; Erwähnungen von `gh project create` im Bootstrap-Kontext werden auf das File-Board umgestellt.

## Acceptance-Kriterien

- **AC1** — `new-project` legt `board/board.yaml`, `board/features/` und `board/stories/` an; leere Ordner werden (z.B. via `.gitkeep`) committet. *(V1)*
- **AC2** — Die initiale `board/board.yaml` enthält `schema_version`, `project_slug` (aus Projektname) und Start-Zähler, so dass die erste Vergabe `F-001`/`S-001` ergibt; konform zu [[board-schema]] V1. *(V2)*
- **AC3** — `.claude/profile.md` wird mit `board: file` angelegt; keine GitHub-Projekt-Nummer wird gesetzt. *(V3)*
- **AC4** — Der Bootstrap ruft kein `gh project create` mehr auf; kein Restpfad erwartet eine Board-Nummer. *(V4)*
- **AC5** — Direkt nach dem Bootstrap (leeres Board) ist `board lint` grün (Exit 0). *(V5)*
- **AC6** — Die Skelett-Anlage nutzt die `board`-CLI, wo ein Init-Verb verfügbar ist; sonst schreibt der Bootstrap minimales `board.yaml` strikt nach [[board-schema]] V1. *(V6)*
- **AC7** — Bootstrap-Doku/Templates beschreiben das File-Board als Standard; `gh project create`-Erwähnungen im Bootstrap-Kontext sind auf das File-Board umgestellt. *(V7)*

## Verträge

### Skelett-Layout (board-subsystem §6)
```
<neues-repo>/
  board/
    board.yaml          # schema_version, project_slug, next_feature_id, next_story_id
    features/.gitkeep
    stories/.gitkeep
  .claude/profile.md    # board: file
```

### Profil-Feld
```
board: file             # statt einer GitHub-Projekt-Nummer
```

## Edge-Cases & Fehlerverhalten

- **Repo hat bereits `board/`** → Bootstrap bricht nicht ab, sondern lässt bestehende Dateien unangetastet (idempotent) und meldet „Board existiert bereits".
- **Projektname mit Sonderzeichen** → `project_slug` wird auf kebab-case normalisiert.
- **Kein `git`/kein Repo** → wie bisher beim Bootstrap behandelt (ausserhalb dieser Spec).

## NFRs

- **Idempotenz:** wiederholter Bootstrap ändert ein bestehendes Board nicht.
- **Offline:** keine Netzwerk-/GitHub-Abhängigkeit beim Board-Bootstrap.

## Nicht-Ziele

- Dateiformat selbst ([[board-schema]]).
- CLI-Verben ([[board-cli]]).
- Adopt-Funde als Stories (eigener `adopt`-Pfad, hier nur Anschluss benannt).
- Migration bestehender GitHub-Boards ([[board-github-export]]).

## Abhängigkeiten

- [[board-schema]] — `board.yaml`-Format des Skeletts.
- [[board-cli]] — Anlage über CLI (sofern Init-Verb vorhanden).
- `docs/architecture/board-subsystem.md` §6, §8 — bindendes Detailkonzept.
