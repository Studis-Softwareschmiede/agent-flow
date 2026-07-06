---
id: board-area-ops
title: Bereichs-Operationen — board area list/merge/split + archive-done-stories
status: active
version: 1
spec_format: use-case-2.0
area: board
---

# Spec: Bereichs-Operationen  (`board-area-ops`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Diese Spec ergänzt die `board`-CLI ([[board-cli]]) um die **Bereichs-Verwaltungs-Verben**: `board area list`, `board area merge`, `board area split` und `board archive-done-stories`. Das Bereichs-Datenmodell (`areas.yaml`, Feature-Kopplung, Archiv-Semantik) definiert [[board-areas]]; diese Spec definiert die **Operationen** darauf. Die CLI bleibt die **einzige** Stelle, die das Board-/Bereichs-Format kennt.

## Zweck

Bereiche entwickeln sich: sie werden zusammengelegt (`merge`), aufgeteilt (`split`) und erledigte Storys werden aus dem aktiven Board archiviert (`archive-done-stories`). Diese Verben kapseln diese Lebenszyklus-Operationen deterministisch, idempotent und **ohne** je Dateien zu verschieben oder Spec-IDs zu ändern — die Bereichszuordnung ist ein reines Etikett.

## Kontext / Designnuancen (bindend)

- **Bereichszuordnung ist ein Etikett, NIE Dateiverschiebung.** `merge`/`split` schreiben ausschliesslich `areas.yaml` + die `area`-Etiketten (Feature-`area`, Spec-`area`-Frontmatter, ggf. Ideen-Inbox-Einträge) um. Spec-IDs, Spec-Dateinamen und Board-Dateinamen bleiben **stabil**.
- **`merge` ist vollautomatisch + idempotent.** Zusammenlegen ist eine rein mechanische Umschreibung ohne Rückfrage; ein zweiter identischer Aufruf ändert nichts mehr (idempotent).
- **`split` ist assistiert.** Aufteilen ist nicht mechanisch eindeutig: die CLI schlägt je Artefakt (Spec/Story/Idee) ein Ziel mit Konfidenz vor, weist **eindeutige** Fälle direkt zu und legt **unklare** Fälle als maschinenlesbaren Fragenkatalog im etablierten Format `{stage,id,frage,quelle,optionen}` (`board/fragenkatalog.schema.json`) vor.
- **`archive-done-stories` betrifft nur Storys.** Bereichs-Features werden nie archiviert ([[board-areas]] AC3/AC4). Archivieren = die `Done`-Story-YAML nach `board/stories/archive/` verschieben (git-erhalten, aus dem aktiven `list`/`next`/`rollup`-View entfernt). *(Konservative Annahme: eigenes `archive/`-Unterverzeichnis statt eines neuen Status; so bleibt der Status-Enum unverändert und die Historie im git erhalten.)*
- **Nur lesende Verben sind token-frei/deterministisch.** `list`/`merge`/`archive-done-stories` laufen ohne LLM. `split`s Ziel-Vorschlag darf heuristisch (token-frei, z.B. Namens-/Label-Ähnlichkeit) sein; die endgültige Zuordnung unklarer Fälle entscheidet der Mensch über den Fragenkatalog.
- **Single-Writer bleibt gewahrt.** Diese Verben ändern **nicht** den Story-`status` (das bleibt `/flow`, [[board-cli]] V9); `archive-done-stories` verschiebt nur bereits `Done`-Storys.

## Main Success Scenario

1. `board area list` gibt die Bereiche aus `areas.yaml` als sortiertes JSON aus (für Requirement-Gate, Dropdowns, andere Verben).
2. `board area merge <a> <b> <ziel>` legt Bereich `<a>` und `<b>` unter `<ziel>` zusammen: `areas.yaml` wird angepasst und alle `area:`-Etiketten von `<a>`/`<b>` auf `<ziel>` umgeschrieben.
3. `board area split <a> <a1> <a2>` listet alle Artefakte von `<a>`, weist eindeutige zu und legt die unklaren als Fragenkatalog vor.
4. `board archive-done-stories` verschiebt alle `Done`-Storys nach `board/stories/archive/`; die Bereichs-Features bleiben.

## Alternative Flows

### A1: split — nur eindeutige Fälle
- Alle Artefakte sind eindeutig zuordenbar → leerer Fragenkatalog (leere Liste), alle Etiketten direkt umgeschrieben, kein Rückfrage-Bedarf.

### E1: unbekannter Bereich
- `merge`/`split` mit einem Quell-/Ziel-Bereich, der nicht in `areas.yaml` existiert → Fehler, **kein** Schreiben, Exit ≠ 0.

### E2: split-Ziel existiert noch nicht
- `<a1>`/`<a2>` sind neue Bereiche → `split` legt sie in `areas.yaml` an (erbt `description`-Platzhalter + nächste `order`); der Quell-Bereich `<a>` wird entfernt, sobald alle Artefakte zugeordnet sind (offene Fragen → `<a>` bleibt bis zur Beantwortung bestehen).

## Acceptance-Kriterien

- **AC1** — `board area list` gibt die Bereiche aus `areas.yaml` als JSON-Array (Felder `id,name,description,order`), sortiert nach `order`, aus. Fehlt `areas.yaml` → leeres Array, Exit 0. Token-frei/deterministisch. *(V1)*
- **AC2** — `board area merge <a> <b> <ziel>` ist vollautomatisch: es schreibt `areas.yaml` (entfernt `<a>`/`<b>`, behält/legt `<ziel>` an) und schreibt **mechanisch** alle `area`-Etiketten (Feature-`area`, Spec-`area`-Frontmatter, Ideen-Inbox-Einträge) von `<a>`/`<b>` auf `<ziel>` um. Es ist **idempotent** (zweiter Aufruf ändert nichts) und verschiebt **keine** Dateien / ändert **keine** Spec-IDs. Unbekannter Bereich → kein Schreiben, Exit ≠ 0. *(V2)*
- **AC3** — `board archive-done-stories` verschiebt jede Story mit `status=Done` nach `board/stories/archive/` (git-erhalten), aktualisiert die betroffenen Feature-Rollups und lässt Bereichs-Features unberührt (nie archiviert). Storys mit anderem Status bleiben unangetastet. Idempotent (zweiter Aufruf: nichts mehr zu archivieren). *(V3, [[board-areas]] AC4)*
- **AC4** — `board area split <a> <a1> <a2>` ist assistiert: es listet alle Artefakte von `<a>` (Specs mit `area=<a>`, Storys unter Features mit `area=<a>`, Ideen-Inbox-Einträge mit `area=<a>`) mit **Ziel-Vorschlag** (`<a1>`|`<a2>`) und **Konfidenz**; eindeutige Fälle werden direkt zugeordnet (Etikett umgeschrieben), unklare Fälle als maschinenlesbarer Fragenkatalog `{stage,id,frage,quelle,optionen}` (`board/fragenkatalog.schema.json`) ausgegeben. Es verschiebt **keine** Dateien / ändert **keine** Spec-IDs. Unbekannter Quell-Bereich → kein Schreiben, Exit ≠ 0. *(V4)*
- **AC5** — Alle vier Verben schreiben atomar (kein halber Zustand bei Fehler); `list`, `merge`, `archive-done-stories` sind deterministisch ohne LLM; `split`s Ziel-Heuristik ist token-frei. Bei ungültiger Eingabe wird NICHTS geschrieben, Exit ≠ 0. *(V5)*

## Verträge

### Verb-Übersicht (Ergänzung zu [[board-cli]] §7)
```
board area list                        → JSON-Array (id, name, description, order) | []
board area merge <a> <b> <ziel>        → geänderte areas.yaml + umgeschriebene Etiketten (idempotent)
board area split <a> <a1> <a2>         → Zuordnungs-Report + Fragenkatalog (JSON) für unklare Fälle
board archive-done-stories             → Liste archivierter Story-IDs
```

### `split`-Fragenkatalog (wiederverwendet `board/fragenkatalog.schema.json`)
```json
[
  {
    "stage": "split",
    "id": "split-1",
    "frage": "Zu welchem Bereich gehört Spec X?",
    "quelle": "docs/specs/x.md",
    "optionen": ["<a1>", "<a2>"]
  }
]
```
*(Konservative Annahme: `stage` nutzt den Wert `split`; sollte das etablierte Enum in `board/fragenkatalog.schema.json` `split` nicht führen, wird es dort um `split` ergänzt — die Feldmenge `{stage,id,frage,quelle,optionen}` bleibt der bindende Vertrag.)*

### `split`-Zuordnungs-Report (Implementierungsdetail, nicht Teil des Fragenkatalog-Schemas)
```json
{
  "quell_bereich": "<a>",
  "ziel_a1": "<a1>",
  "ziel_a2": "<a2>",
  "zuordnungen": [
    {"typ": "spec|feature|story|idee", "id": "…", "quelle": "…", "ziel_vorschlag": "<a1>|<a2>|null", "konfidenz": "hoch|mittel|niedrig", "zugeordnet": true}
  ],
  "fragenkatalog": [ ],
  "quell_bereich_entfernt": true
}
```
*(Feldnamen des Reports selbst sind Implementierungsfreiheit — nur die `fragenkatalog`-Einträge folgen dem bindenden Vertrag oben. `typ: "story"` ist rein informativ: Storys tragen kein eigenes `area`-Feld, siehe Edge-Cases.)*

### Archiv-Ablage
```
board/stories/archive/S-###-<slug>.yaml   # verschobene Done-Storys (aus aktivem View entfernt)
```

## Edge-Cases & Fehlerverhalten

- **`merge` von `<a>`==`<ziel>`** → `<b>` wird in `<a>` eingegliedert; kein Fehler.
- **`merge`, wenn `<ziel>` noch nicht existiert** → `<ziel>` wird in `areas.yaml` angelegt (nächste `order`), dann `<a>`/`<b>` eingegliedert. *(Spec-Präzisierung: `name`/`description` des neuen `<ziel>`-Eintrags werden von `<a>` übernommen, falls `<a>` in `areas.yaml` existiert, sonst von `<b>`; `order` = höchste bestehende `order` + 1.)*
- **`merge`-Gültigkeitsprüfung („unbekannter Bereich", E1) — Spec-Präzisierung:** `areas.yaml` ist die einzige Quelle gültiger Bereichs-`id`s (AC1). Ein Aufruf gilt nur dann als **unbekannter Bereich** (Fehler, kein Schreiben, Exit ≠ 0), wenn **weder** `<a>` **noch** `<b>` **noch** `<ziel>` aktuell als Eintrag in `areas.yaml` existiert. Ist mindestens einer der drei bekannt (z. B. `<ziel>` existiert bereits aus einem vorherigen Merge-Lauf, oder `<a>`==`<ziel>` und bekannt), läuft der Merge durch; ein bereits fehlender `<a>`/`<b>`-Eintrag gilt dabei als „nichts mehr zu entfernen" (kein Fehler). Diese Regel macht einen zweiten, identischen Aufruf idempotent (AC2), ohne die Kernaussage von E1 (garantiert unbekannte Eingabe → Fehler) zu verletzen.
- **`archive-done-stories` ohne `Done`-Storys** → leere Ausgabe, Exit 0 (nichts zu tun).
- **`split` mit offenen Fragen** → der Quell-Bereich `<a>` bleibt in `areas.yaml`, bis alle Artefakte zugeordnet sind (kein Datenverlust).
- **`split`-Ziel-Bereiche, die noch nicht existieren** → `<a1>`/`<a2>` werden — unabhängig von offenen Fragen — sofort in `areas.yaml` angelegt (Platzhalter-`description`, nächste `order` je Ziel), damit ein bereits zugeordnetes Artefakt nie auf einen fehlenden Bereich zeigt (kein `AREA-UNKNOWN`-Zwischenzustand). Ist `<a1>` oder `<a2>` identisch mit `<a>`, wird `<a>` beim Entfernen übersprungen (der wiederverwendete Bereich bleibt bestehen).
- **`split`-Artefakttyp Story — Spec-Präzisierung (bindend an Kontext-Abschnitt oben):** Nur Feature-`area`, Spec-`area`-Frontmatter und Ideen-Inbox-`- area:`-Einträge sind schreibbare Bereichs-Etiketten (wie bei `merge`, AC2). Eine Story trägt **kein** eigenes `area`-Feld — ihre Bereichszugehörigkeit hängt an ihrem Eltern-Feature. Storys erscheinen im `split`-Report daher **nur informativ**, mit demselben Ziel-Vorschlag/Konfidenz-Ergebnis wie ihr Eltern-Feature; sie werden nicht separat befragt oder umgeschrieben (kein Story-Reparenting — Kern-CRUD-Verben sind laut Nicht-Ziele dieser Spec ausgeschlossen).
- **`split`, wenn `<a1>`==`<a2>`** → ungültige Eingabe (kein sinnvoller Split), Fehler, kein Schreiben, Exit ≠ 0 (AC5).
- **Story ist bereits in `archive/`** → wird von `list`/`next`/`rollup` ignoriert; erneutes `archive-done-stories` fasst sie nicht an.
- **`merge`/`split` ändern nie Story-`status` oder Spec-`id`** → Drift-Gate bleibt intakt.

## NFRs

- **Idempotenz:** `merge`/`archive-done-stories` sind wiederholbar ohne Nebeneffekt.
- **Determinismus:** `list`/`merge`/`archive` ohne LLM; `split`-Heuristik token-frei und reproduzierbar.
- **Nachvollziehbarkeit:** jede Umschreibung ist ein git-Diff; keine stillen Datei-/ID-Änderungen.

## Nicht-Ziele

- Das Bereichs-Datenmodell + Lint selbst ([[board-areas]]).
- Kern-CRUD-Verben (`feature/story add`, `set`, `next`, …) ([[board-cli]]).
- Das Requirement-Eingangs-Gate ([[requirement-area-intake]]).
- Automatische Löschung von Features/Storys/Specs (nie autonom — Owner-Freigabe).

## Abhängigkeiten

- [[board-areas]] — Bereichs-Datenmodell (`areas.yaml`, Feature-Kopplung, Archiv-Semantik), auf dem diese Operationen arbeiten.
- [[board-cli]] — die CLI, in die diese Verben integriert werden (format-kennende Stelle, Single-Writer).
- [[requirement-area-intake]] — Konsument von `board area list`; Quelle der Ideen-Inbox-Einträge, die `merge`/`split` mit-umschreiben.
- `board/fragenkatalog.schema.json` — etabliertes maschinenlesbares Frageformat, das `split` wiederverwendet.
</content>
