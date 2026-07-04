---
id: board-github-export
title: GitHub-Board-Export + Cut-Runbook — einmalige Big-Bang-Migration nach board/
status: active
version: 1
---

# Spec: GitHub-Board-Export + Cut-Runbook  (`board-github-export`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Board-Subsystem ist in `docs/architecture/board-subsystem.md` spezifiziert (bindend, §10). Diese Spec beschreibt das **einmalige** Export-Tool (`board export-github`), das ein GitHub Project v2 in `board/`-Dateien überführt, die Feature-Heuristik (je Spec/Label-Cluster) und das Cut-Runbook (Export → Lint → Review-PR → Cut → dev-gui) mit git-Rückfallebene.

## Zweck

Den Big-Bang-Schnitt von GitHub-Projects auf das File-Board absichern: ein einmaliges Tool liest das aktuelle GitHub Project v2 (Issues, Status, Priority, depends, Spec-Refs) und schreibt `board/features/` + `board/stories/`, gruppiert Issues heuristisch zu Features, und ein dokumentiertes Runbook führt den Cut so durch, dass ein Rollback per `git revert` jederzeit möglich bleibt.

## Kontext / Designnuancen (bindend)

- **Einmalig, nicht laufend.** Kein Dauer-Sync GitHub↔Files. Der Export ist ein einzelner Lauf je Repo, gefolgt von einem Cut-PR (board-subsystem §10).
- **Feature-Heuristik.** Ein Auto-Feature je Spec-Datei bzw. Label-Cluster; lieber grob gruppieren, Owner benennt/schärft im Cut-PR nach (§10[1], §11).
- **git als Rückfallebene.** Der Export ist *ein* git-Commit; das GitHub-Board wird nach dem Cut **archiviert (nicht gelöscht)**. Rollback = `git revert` des Cut-PR + Profil zurück auf Board-Nummer. Kein Parallelbetrieb (§10).
- **Lint muss grün sein.** Nach dem Export prüft `board lint` parent/depends/AC-Integrität; der Cut-PR geht erst bei grünem Lint raus (§10[2]).
- **Reihenfolge der Repos.** Zuerst `dev-gui` (Dogfooding), dann ein kleines Projekt, dann der Rest (§10).
- **Verb hinter `board export-github`.** Das CLI-Verb ([[board-cli]] V11) ruft dieses Verhalten auf.
- Konservative Annahme: GitHub-Status-Namen mappen 1:1 auf die Story-Status (`To Do|In Progress|Blocked|In Review|Done`); `depends: #n`-Freitext im Body wird per Regex extrahiert und auf die exportierten Story-IDs umgesetzt. `Spec:`/`implements:`-Marker im Body werden für `spec`/`implements` übernommen.

## Verhalten

### V1 — GitHub-Board lesen
`board export-github` liest das in `profile.md` referenzierte GitHub Project v2: je Item Titel, Body, Status, Priority, Labels, und die Freitext-Marker `Spec:`, `implements:`, `depends: #n`.

### V2 — Story je Issue
Jedes GitHub-Item wird zu einer Story-YAML: neue `S-###` (über `board.yaml`-Zähler), `title`, `status` (1:1-Mapping), `priority`, `labels`, `spec`/`implements` aus den Body-Markern. Der ursprüngliche Issue-Bezug wird zur Nachvollziehbarkeit vermerkt (z.B. `labels`/Kommentar `from-issue:#n`).

### V3 — Feature-Heuristik
Issues werden zu Auto-Features gruppiert: primär je referenzierter Spec-Datei (`Spec:`), ersatzweise je Label-Cluster. Je Gruppe entsteht ein Feature-YAML (`F-###`, `title` aus Spec/Cluster, `status` aus dem Rollup der Kind-Stories, `goal`-Platzhalter für Owner-Nachbenennung). Jede Story bekommt das passende `parent`.

### V3a — Single-Feature-Modus (`--single-feature <name>`)
Ist das optionale Flag `--single-feature <name>` gesetzt, wird die Heuristik aus V3 übersprungen: **alle** exportierten Stories kommen unter EIN Feature mit diesem `title` (z.B. `Initial`); jede Story trägt dessen `parent`. Bootstrap-Strategie für gewachsene Boards (etwa bei 1:1-Spec-Story-Beziehungen, wo die Heuristik kaum gruppiert) — der Owner schneidet im/nach dem Cut-PR feinere Features heraus. Unabhängig vom Modus werden Spec-Marker beim Parsen **bereinigt** (Backticks, `(§…)`-Annotation, Trailing-Satzzeichen → reiner Pfad); zeigt der bereinigte Pfad auf eine nicht existierende Datei → `spec: null` (Lint: `WARN STORY-UNSPEC`, kein `FEHLER SPEC-MISSING`) + Report-Hinweis.

### V4 — depends auflösen
`depends: #n`-Freitext wird auf die exportierten Story-IDs umgesetzt (`#n` → `S-###`). Lässt sich `#n` nicht auf ein exportiertes Item abbilden, wird der Eintrag verworfen und im Lauf-Report als Warnung gelistet (nie als unauflösbare Referenz geschrieben).

### V5 — board.yaml schreiben
`board/board.yaml` wird angelegt/aktualisiert (`schema_version`, `project_slug`, Zähler auf die höchste vergebene Nummer) — konform zu [[board-schema]] V1.

### V6 — Lint-Gate
Nach dem Export läuft `board lint`; der Export-Lauf meldet das Ergebnis. Erst grüner Lint (Exit 0, höchstens Warnungen) qualifiziert für den Cut-PR. Lint-Fehler → der Lauf gibt sie aus, der Owner korrigiert vor dem PR.

### V7 — Lauf-Report
Der Export gibt einen Report aus: Anzahl Features/Stories, gebildete Cluster, verworfene `depends`, nicht zuordenbare Spec-Refs — als Review-Hilfe für den Cut-PR.

### V8 — Cut-Runbook (dokumentiert)
Ein dokumentiertes Runbook (board-subsystem §10) beschreibt die Schritte: [0] Voraussetzung (Agents/CLI auf File-Backend, getestet) → [1] Export → [2] `board lint` grün → [3] Review-PR „Board → Files" → [4] Cut: PR mergen, `profile.md` `board: file`, GitHub-Board archivieren (nicht löschen) → [5] dev-gui-Aggregator aktivieren.

### V9 — Rollback-Pfad (dokumentiert)
Das Runbook dokumentiert die Rückfallebene: `git revert` des Cut-PR + `profile.md` zurück auf die Board-Nummer; das archivierte (nicht gelöschte) GitHub-Board dient als Stand. Kein laufender Sync nötig.

### V10 — Idempotenz/Schutz
Ein zweiter Export-Lauf auf ein bereits gefülltes `board/` legt nicht blind doppelt an: er bricht ab oder verlangt ein explizites Flag (kein versehentliches Duplizieren).

## Acceptance-Kriterien

- **AC1** — `board export-github` liest das in `profile.md` referenzierte GitHub Project v2 (Titel, Body, Status, Priority, Labels, Marker `Spec:`/`implements:`/`depends:#n`). *(V1)*
- **AC2** — Jedes GitHub-Item wird zu einer Story-YAML mit neuer `S-###`, 1:1-Status-Mapping, `priority`, `labels`, `spec`/`implements` aus den Body-Markern; der Issue-Bezug bleibt nachvollziehbar. *(V2)*
- **AC3** — Issues werden zu Auto-Features gruppiert (primär je Spec-Datei, sonst Label-Cluster); je Gruppe ein Feature-YAML, jede Story trägt das passende `parent`. Ist `--single-feature <name>` gesetzt, entfällt die Heuristik und alle Stories kommen unter EIN Feature `<name>`; Spec-Marker werden bereinigt, eine nicht existierende Spec-Datei → `spec: null` (WARN STORY-UNSPEC), nie ein nicht existenter Pfad als `spec`. *(V3, V3a)*
- **AC4** — `depends:#n` wird auf exportierte Story-IDs umgesetzt; nicht abbildbare Referenzen werden verworfen + im Report gewarnt (nie als unauflösbar geschrieben). *(V4)*
- **AC5** — `board/board.yaml` wird konform zu [[board-schema]] V1 mit Zählern auf die höchste vergebene Nummer geschrieben. *(V5)*
- **AC6** — Nach dem Export läuft `board lint`; nur grüner Lint (Exit 0) qualifiziert für den Cut-PR; Fehler werden ausgegeben. *(V6)*
- **AC7** — Der Lauf gibt einen Report aus (#Features/#Stories, Cluster, verworfene depends, nicht zuordenbare Spec-Refs). *(V7)*
- **AC8** — Ein dokumentiertes Cut-Runbook beschreibt die Schritte [0]–[5] aus board-subsystem §10 (inkl. Profil-Umstellung auf `board: file` und GitHub-Board-Archivierung statt -Löschung). *(V8)*
- **AC9** — Das Runbook dokumentiert den Rollback (`git revert` Cut-PR + Profil zurück auf Board-Nummer; archiviertes GitHub-Board als Stand). *(V9)*
- **AC10** — Ein zweiter Export-Lauf auf ein gefülltes `board/` dupliziert nicht blind (Abbruch oder explizites Flag erforderlich). *(V10)*

## Verträge

### Marker-Extraktion (aus Issue-Body)
```
Spec: docs/specs/<slug>.md     → story.spec
implements: AC1, AC2           → story.implements
depends: #12, #15              → story.depends (→ S-### nach V4)
```

### Lauf-Report (Beispiel)
```
features: 4   stories: 27
clusters:  provisioning(8) · metrics(11) · secrets(6) · misc(2)
warnings:  depends #99 → kein Export-Item (verworfen)
lint:      GREEN
```

## Edge-Cases & Fehlerverhalten

- **Kein GitHub-Board im Profil** (`board: file` bereits gesetzt) → Export bricht ab mit Hinweis „kein gh-Board zu exportieren".
- **Issue ohne `Spec:`-Marker** → landet im `misc`-Feature (Label-Cluster oder Sammel-Feature); Owner sortiert im Cut-PR um.
- **Status-Name unbekannt** (kein 1:1-Mapping) → konservativ auf `To Do` + Report-Warnung.
- **Doppelte Issue-Titel** → eigene `S-###` je Issue (IDs eindeutig), Slug ggf. mit Suffix.
- **Rate-Limit/PAT-Fehler** → Lauf bricht sauber ab, schreibt KEIN halbes `board/` (atomar oder gar nicht).

## NFRs

- **Vollständig im Diff sichtbar:** der Export ist ein git-Commit; der Cut-PR zeigt alles (board-subsystem §10[3]).
- **Reversibel:** Rollback per `git revert`; GitHub-Board archiviert, nicht gelöscht.
- **Einmalig:** kein Dauer-Sync, keine laufende GitHub-Abhängigkeit nach dem Cut.

## Nicht-Ziele

- Laufender GitHub↔Files-Sync (bewusst nicht, Big-Bang).
- Dateiformat/Lint-Regeln selbst ([[board-schema]], [[board-cli]]).
- /flow-Backend-Umstellung ([[flow-board-backend]]) — Voraussetzung [0], nicht Teil dieser Spec.
- dev-gui-Aggregation ([[dev-gui-board-aggregator]]) — Runbook-Schritt [5], eigene Spec.

## Abhängigkeiten

- [[board-cli]] — `board export-github`-Verb + `board lint` für das Gate.
- [[board-schema]] — Zielformat des Exports.
- [[flow-board-backend]] — muss vor dem Cut umgestellt + getestet sein (Runbook [0]).
- `docs/architecture/board-subsystem.md` §10, §11 — bindendes Detailkonzept.
