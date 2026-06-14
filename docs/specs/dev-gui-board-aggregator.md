---
id: dev-gui-board-aggregator
title: dev-gui Board-Aggregator — read-only Multi-Repo-Scan, Index/Cache, Projekt→Feature→Story-Übersicht
status: active
version: 1
---

# Spec: dev-gui Board-Aggregator  (`dev-gui-board-aggregator`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Board-Subsystem ist in `docs/architecture/board-subsystem.md` spezifiziert (bindend, §9). Diese Spec beschreibt den `dev-gui`-Board-Aggregator: ein **read-only** Multi-Repo-Scan der `board/`-Ordner, ein flüchtiger Index/Cache (kein Zweit-Store), und eine dreistufige Übersicht **Projekt → Feature → Story** mit Rollup je Feature.

## Zweck

`dev-gui` aggregiert die vielen `board/`-Ordner aller Projekte zu *einer* fabrikweiten Live-Übersicht, ohne die „Dateien = Source of Truth"-Regel zu brechen: Es scannt die Repos read-only, hält den Index nur flüchtig im Speicher und stellt Projekt → Feature → Story mit Status-Spalten, Rollup-Balken und Filtern dar.

## Kontext / Designnuancen (bindend)

- **Read-only.** Der Aggregator liest nur; er schreibt NICHT in `board/`-Dateien. (GUI-Schreibpfad ist bewusst Phase 2, board-subsystem §9.4/§12 „bewusst NICHT in v1".)
- **Kein Zweit-Store.** Der Index ist ein flüchtiger Cache (Speicher/leichtgewichtig); die Dateien bleiben Source of Truth. Re-Scan bei Dateiänderung (Watcher) oder on-demand (§9.2). Kein persistenter DB-Spiegel.
- **Multi-Repo-Scan.** Konfigurierte Repo-Wurzeln (z.B. `~/Git/Studis-Softwareschmiede/*`) werden nach `board/`-Ordnern durchsucht (§9.1).
- **Dreistufige View.** Projekt → Feature → Story mit Status-Spalten, Rollup je Feature, Filter (Projekt, Status, Label) (§9.3).
- **Rollup gespiegelt, nicht neu erfunden.** Der Aggregator zeigt `progress` je Feature; die Rollup-Berechnung selbst ist Sache von `board rollup` ([[board-cli]] V7). Konservative Annahme: Findet der Aggregator stale/fehlende `progress`-Felder, berechnet er den Anzeige-Rollup read-only aus den Kind-Stories (reine Anzeige, keine Datei-Änderung).
- **Robust gegen Defekte.** Ein einzelnes ungültiges Board/Repo darf die Gesamtübersicht nicht zum Absturz bringen; es wird mit Fehlermarkierung übersprungen.

## Verhalten

### V1 — Repo-Scan
Der Aggregator durchsucht die in der dev-gui-Config hinterlegten Repo-Wurzeln read-only nach `board/`-Ordnern und liest je Repo `board.yaml`, alle `features/*.yaml` und `stories/*.yaml`.

### V2 — Index/Cache (flüchtig)
Die gelesenen Daten werden in einem flüchtigen In-Memory-Index gehalten — kein persistenter Zweit-Store. Bei `board/`-Dateiänderung (Watcher) oder on-demand-Trigger wird neu gescannt; der Index wird ersetzt.

### V3 — Aggregat-Modell
Der Index modelliert die Hierarchie Projekt (= Repo) → Feature → Story; jede Story trägt mindestens `id`, `parent`, `title`, `status`, `priority`, `labels`, `spec`, `dispo_est`/`dispo_act` (sofern in der YAML vorhanden).

### V4 — Übersichts-View
Die GUI zeigt eine dreistufige Übersicht Projekt → Feature → Story mit Status-Spalten (Story-Status-Lebenszyklus) und ist über alle gescannten Projekte aggregiert (board-subsystem §9.3).

### V5 — Rollup-Balken je Feature
Je Feature wird ein Fortschritts-Rollup angezeigt (z.B. „2/3 done"). Ist `progress` in der Feature-YAML vorhanden, wird es angezeigt; fehlt/stale → der Aggregator berechnet den Anzeigewert read-only aus den Kind-Story-Status.

### V6 — Filter
Die View filtert nach Projekt, Story-Status und Label (board-subsystem §9.3).

### V7 — Read-only-Garantie
Kein Code-Pfad des Aggregators schreibt in `board/`-Dateien oder legt einen persistenten Cache an. (Schreiben ist Phase 2 und ginge dann ausschliesslich durch die `board`-CLI — nicht Teil dieser Spec.)

### V8 — Fehler-Toleranz
Ein nicht lesbares/ungültiges `board/` (fehlende `board.yaml`, kaputtes YAML) wird mit Fehlermarkierung im UI übersprungen; die übrigen Projekte bleiben sichtbar. Der Scan stürzt nicht ab.

### V9 — Aktualität
Eine Änderung an einer `board/`-Datei spiegelt sich nach Watcher-Trigger bzw. nächstem on-demand-Scan in der View (kein veralteter persistenter Stand).

## Acceptance-Kriterien

- **AC1** — Der Aggregator scannt die konfigurierten Repo-Wurzeln read-only nach `board/`-Ordnern und liest je Repo `board.yaml` + alle `features/*.yaml` + `stories/*.yaml`. *(V1)*
- **AC2** — Die gelesenen Daten liegen in einem flüchtigen In-Memory-Index (kein persistenter Zweit-Store); Re-Scan bei Dateiänderung (Watcher) oder on-demand ersetzt den Index. *(V2)*
- **AC3** — Der Index modelliert Projekt → Feature → Story; jede Story trägt mind. `id,parent,title,status,priority,labels,spec` (+ `dispo_*` falls vorhanden). *(V3)*
- **AC4** — Die GUI zeigt eine dreistufige Übersicht Projekt → Feature → Story mit Status-Spalten, aggregiert über alle gescannten Projekte. *(V4)*
- **AC5** — Je Feature wird ein Fortschritts-Rollup angezeigt; vorhandenes `progress` wird genutzt, fehlend/stale → read-only aus Kind-Story-Status berechnet. *(V5)*
- **AC6** — Die View filtert nach Projekt, Story-Status und Label. *(V6)*
- **AC7** — Kein Code-Pfad des Aggregators schreibt in `board/`-Dateien oder legt einen persistenten Cache an. *(V7)*
- **AC8** — Ein ungültiges/nicht lesbares `board/` wird mit Fehlermarkierung übersprungen; die übrigen Projekte bleiben sichtbar, der Scan stürzt nicht ab. *(V8)*
- **AC9** — Eine `board/`-Dateiänderung spiegelt sich nach Watcher-Trigger bzw. nächstem on-demand-Scan in der View. *(V9)*

## Verträge

### Config (dev-gui)
```
board_roots: ["~/Git/Studis-Softwareschmiede"]   # Wurzeln, unter denen board/-Ordner gesucht werden
```

### Aggregat (read-only, je Projekt)
```
project: { slug, repo_path, features: [
  { id, title, status, priority, progress, stories: [
    { id, parent, title, status, priority, labels[], spec, dispo_est, dispo_act }
  ]}
]}
```

## Edge-Cases & Fehlerverhalten

- **Repo ohne `board/`** → kein Board-Projekt, übersprungen (kein Fehler).
- **`board.yaml` fehlt / YAML kaputt** → Projekt mit Fehlermarkierung, Rest läuft (V8).
- **Story mit `parent`, das es nicht gibt** → Story unter „verwaist"/Fehlermarkierung gruppiert, kein Absturz.
- **Sehr viele Repos** → Scan linear; Watcher hält den Index aktuell, kein Voll-Scan je Request nötig.
- **Symlinks/zyklische Pfade** beim Scan → werden ignoriert/abgeschnitten (kein Endlos-Scan).

## NFRs

- **Read-only & SoT-Treue:** Dateien bleiben einzige Wahrheit; Index ist nur Sicht (board-subsystem §9).
- **Robustheit:** ein defektes Board kippt die Gesamtsicht nicht.
- **Reaktivität:** Watcher-getriebene Aktualisierung statt teurem Dauer-Polling.

## Nicht-Ziele

- GUI-Schreibpfad (Phase 2, durch die `board`-CLI — board-subsystem §9.4/§12).
- Rollup-Berechnung als Datei-Schreibvorgang ([[board-cli]] V7).
- Entfernte Repos über Netzwerk (board-subsystem §12 „bewusst NICHT in v1").
- Persistenter zentraler DB-Store.

## Abhängigkeiten

- [[board-schema]] — Dateiformat, das der Aggregator liest.
- [[board-cli]] — Quelle der Rollup-Semantik (Anzeige spiegelt sie).
- `docs/architecture/board-subsystem.md` §9 — bindendes Detailkonzept.
