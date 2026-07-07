# Obsidian-Ingest-Subsystem — Notizen als Requirement-Quelle der Fabrik

> **Status:** akzeptiert (Konzept), **noch nicht gebaut**. **Erweitert 07.07.2026 (Idea-Roundtrip):** ID-Kette
> `IDEA→C→Spec→BR→Story→@trace`, definierte Vault-Schreibzonen (§4b) und `--audit`-Modus (§5a); der
> Rückkanal Repo→Obsidian lebt als Stufe 3 in `reconcile-subsystem.md` §3.
> Quer-Achse wie `reconcile-subsystem.md` /
> `traceability-subsystem.md`. Skill (Arbeitstitel) `/agent-flow:from-notes` — orchestriert Notiz→Konzept→Spec→Stories.
> Sprach-**neutral** (der Notiz-Inhalt ist projektfachlich, das Subsystem selbst ist es nicht).
> **Scope-Grenze (SR — Cross-Repo):** dieses Subsystem ist NUR die **Fabrik-seitige Pipeline-Fähigkeit** (agent-flow).
> Die Bedienung/GUI (Obsidian-Pfad in den Settings, dritter Projekt-Anlage-Weg „aus Obsidian-Notizen", Anzeige +
> Beantwortung des Fragenkatalogs) ist eine **separate dev-gui-Story** (dev-gui-Repo) und wird **hier nicht** als
> Item angelegt — nur die **Schnittstelle** (Skill-Aufruf + Fragenkatalog-Rückgabeformat) wird so beschrieben, dass
> dev-gui sauber andockt (§6).

## 1. Zweck & Problem

Der `requirement`-Fluss (CONCEPT §4a/§4d) startet heute aus **einer getippten vagen Anforderung**. Viele Ideen
entstehen aber vorgelagert als **freie Ideensammlung** in einem Notiz-Vault (Obsidian): pro Ideen-Projekt ein
Ordner mit mehreren `.md`-Notizen (Konzeptphase, teils KI-gestützt). Diese Notizen sollen **direkt** in den
bestehenden Pfad Konzept → Spezifikation → Story einspeisbar sein — als **zusätzliche** Eingabeform, nicht als
Ersatz der vagen Anforderung.

**Kernrisiko: Fehler pflanzen sich fort.** Notizen sind unfertige, teils widersprüchliche Gedanken. Übersetzt die
Fabrik sie ungenau nach `concept.md`, erben Spec und Stories den Fehler. Darum ist die **erste Übersetzung
(Notiz→Konzept) der kritische Punkt** und wird bewusst präzise geführt (niedrige Nachfrage-Schwelle) — lieber
einmal mehr fragen als am Ende viele Kleinkorrekturen.

Zwei Fähigkeiten fallen an, die sich eine gemeinsame Basis (Notiz-Reader + Fragenkatalog-Gate) teilen:

| Fähigkeit | Richtung | Autorität | Wann |
|---|---|---|---|
| **Ingest** (dies, §3) | Notiz → Doku/Board | Notiz **erzeugt** initial Konzept/Spec/Stories | Erst-Verknüpfung + Re-Ingest |
| **Re-Sync** (§5) | Notiz ↔ Doku (nur Diff) | Notiz **überschreibt nie automatisch** — User entscheidet | wiederholt, on-demand |

## 2. Auslöser — dünner Button, Logik in der Fabrik (dritter Weg)

Wie „Board abarbeiten" (`/agent-flow:flow`) und „Änderung erfassen" (`/agent-flow:requirement`) ist der
Auslöser ein **dünner Button** (dev-gui) im „Spezifikation"-Reiter bzw. der Projekt-Anlage, der einen
**Fabrik-Befehl** im Projekt-Terminal startet — Arbeitstitel **`/agent-flow:from-notes <ordnerpfad>`**. Er ist
der **dritte Front-Door** neben `new-project`/`init` und `requirement`. Die gesamte Logik (Notizen lesen,
übersetzen, Fragenkatalog stellen, committen) lebt in **agent-flow**; dev-gui ruft sie nur auf.

## 3. Drei Stufen — je Stufe ein gesammelter Fragenkatalog

Die Pipeline verarbeitet den Notiz-Korpus in drei Stufen. Jede Stufe läuft **automatisch durch, wenn die
Eingabe klar und widerspruchsfrei ist**; nur wenn Unklarheiten/Widersprüche auftreten, hält sie an.

```
Notiz-Korpus ──(a)──▶ docs/concept.md ──(b)──▶ docs/specs/<feature>.md ──(c)──▶ Board-Items/Stories
             [Katalog a]              [Katalog b, +architekt]            [Katalog c] (via requirement)
```

- **Stufe a — Notiz → `docs/concept.md`.** Konsolidiert den Notiz-Korpus zum Konzept (Problem · Nutzer · Ziele ·
  Nicht-Ziele · Scope). **Kritischste Stufe** → **niedrigste Nachfrage-Schwelle** (jede Mehrdeutigkeit im
  Ideen-Text wird eher zur Frage als zur stillen Annahme). **ID-Vergabe:** Ideennotizen ohne `idea_id` erhalten
  eine stabile **`IDEA-NNN`** (Frontmatter-Stempel, §4b); jeder erzeugte Konzeptabschnitt erhält eine ID
  **`C-NNN`** mit Herkunftsvermerk `(← IDEA-NNN)`. Nach Übernahme stempelt die Stufe das Notiz-Frontmatter:
  `idea_status: adopted`, `last_sync`, `sync_hash`, Referenz auf `C-NNN` — Grundlage für Re-Sync (§5),
  Audit (§5a) und den Rückkanal (`reconcile` Stufe 3).
- **Stufe b — Konzept → Spec(s).** Leitet je Capability eine `docs/specs/<feature>.md` aus dem Konzept ab
  (Vorlage `templates/_docs/specs/_template.md`, `spec_format`-Stempel, nummerierte AC). Wo tiefes
  Architektur-Detail nötig ist, wird der **`architekt`** (→ `docs/architecture.md` bzw.
  `docs/architecture/<subsystem>.md`) beteiligt, bei Datenmodell der **`dba`**.
- **Stufe c — Spec → Board.** Zerlegt die Spec(s) in Board-Items/Stories — **über den bestehenden
  `requirement`-Agenten** (kein zweiter Zerlege-Pfad): jedes Item zeigt auf **Spec + AC-Nummern**, To Do.

**Fragenkatalog-Gate (die gemeinsame Mechanik).** Beim Übergang jeder Stufe werden Unklarheiten/Widersprüche
**gesammelt** und als **genau EIN Fragenkatalog** vorgelegt (nicht einzeln sofort erfragt). Der User arbeitet den
Katalog **am Stück** ab; **erst danach** wird das Stufen-Ergebnis committet. Sind keine Fragen offen, läuft die
Stufe ohne Katalog durch. **Commit pro Stufe** (nicht am Ende in einem Rutsch) → Zwischenstände sind durable,
der Lauf ist jederzeit fortsetzbar (analog zum Board als persistentem Zustand).

## 4. Wiederholbare Quelle — `obsidian_source` im Profil

Der verknüpfte Ordner bleibt **am Projekt vermerkt** (`.claude/profile.md`-Frontmatter `obsidian_source: <pfad>`),
**analog zur Board-Referenz**. So ist er für spätere Läufe (Re-Ingest **und** Re-Sync) verfügbar, ohne den Pfad
erneut zu übergeben. Additiv/optional: bestehende Profile ohne Feld bleiben gültig; die vage-Anforderung-Eingabe
bleibt unverändert. **Precedence:** übergebenes Ordner-Argument > `obsidian_source` im Profil; fehlt beides →
klarer Abbruch (nichts zu lesen). Wird ein abweichender Pfad übergeben, wird `obsidian_source` aktualisiert.

## 4b. Vault-Schreibzonen — begrenzt schreibend statt rein lesend (Entscheid 07.07.2026)

Die frühere Regel „Vault ist rein lesende Quelle" ist **aufgehoben** — sie verhinderte den geschlossenen
Kreislauf (Repo-first entstandene Inhalte fanden nie nach Obsidian zurück). Stattdessen gilt ein
**Zonen-Modell**: die Fabrik darf in Ideennotizen ausschliesslich **zwei definierte Zonen** anfassen:

1. **Frontmatter-Sync-Felder:** `idea_id` · `idea_status` (`draft | adopted | parked | rejected | superseded`) ·
   `last_sync` · `sync_hash` · Referenz(en) auf `C-NNN`.
2. **Generierter Abschnitt** `## Stand aus Konzept (generiert)` — stabil benannt, wird gepatcht
   (nie Datei-Überschreiben). Einziger Ort für Rückflüsse aus Konzept/Spec.

**Alles andere ist tabu:** die persönliche Ausarbeitung bleibt unantastbar; gelöscht wird nie (Überholtes
wird `superseded` markiert). Neue Ideennotizen darf nur der Rückkanal (`reconcile` Stufe 3) anlegen — als
klar gekennzeichnete, repo-first entstandene Idee (`idea_status: adopted`, Herkunft `C-NNN`).

## 5. Re-Sync — bewusst **kein** Reconcile-Stufe-0, sondern eigener Modus (invertierte Autorität)

Der Re-Sync (`/agent-flow:from-notes --sync`) zeigt Widersprüche zwischen **aktuellem Notiz-Stand** und
**aktuellem Konzept/Spec-Stand** auf und legt sie dem User **zur Entscheidung** vor. Er **borgt die Form** von
Reconcile (ein read-only Erkennungs-Schritt → ein gesammelter Katalog, kein Blind-Overwrite), **invertiert aber
die Autorität**:

| | `/agent-flow:reconcile` | `/agent-flow:from-notes --sync` (dies) |
|---|---|---|
| Achse | **Code ↔ Doku** | **Notiz ↔ Konzept/Spec** |
| Wer ist Wahrheit | **Code** (fertig, maßgebend) | **weder noch** — Notizen sind unfertige Gedanken |
| Bei Divergenz | Doku wird **automatisch** an Code angeglichen, **kein** per-Drift-Prompt | **nichts automatisch** — je Divergenz **User-Entscheid** |
| Ergebnis | genau **ein PR**, Mensch-Gate = finaler Diff-Blick | **ein Fragenkatalog**, Mensch-Gate = **je Divergenz** |

**Entscheidung: eigener Modus, NICHT eine Reconcile-„Stufe 0".** Reconciles Vertrag ist bewusst „Code gewinnt,
kein Einzel-Nachfragen, ein PR" (`reconcile-subsystem.md` §7). Eine notiz-getriebene Stufe mit **entgegengesetzter**
Autorität (nichts automatisch, per-Divergenz-Entscheid) in denselben Skill zu hängen würde diesen klaren Vertrag
verwässern. Der Re-Sync ist deshalb ein **eigener Modus** desselben `from-notes`-Skills, der Reader + Katalog-Gate
mit dem Ingest teilt, aber Reconcile unangetastet lässt.

## 5a. `--audit` — Integritätsprüfung über die ID-Kette (neu, 07.07.2026)

`/agent-flow:from-notes --audit` verlängert die bestehende `@trace`-Traceability
(`traceability-subsystem.md`) nach oben bis zur Idee und prüft die **gesamte Kette auf Lücken und
Widersprüche** — read-only, ändert nichts:

| Ebene | ID | Wo | Status |
|---|---|---|---|
| Idee | `IDEA-NNN` | Frontmatter Ideennotiz (Vault) | **neu** |
| Konzept | `C-NNN (← IDEA-NNN)` | `docs/concept.md` | **neu** |
| Spec | Spec-ID `(← C-NNN)` | `docs/specs/<feature>.md` | besteht |
| Geschäftsregel | `BR-NNN` | `architecture.md` / `data-model.md` | besteht |
| Story | Board-Item (→ Spec-ID) | Board | besteht |
| Code/Test | `@trace <slug>#AC/BR` | Testcode, Coverage-Gate | besteht |

- **Abgeleitete Coverage-Map, nie handgepflegt** (gleiche Philosophie wie das Traceability-Subsystem):
  je Lauf frisch berechnet aus Frontmatter-Scan (Vault via `obsidian_source`) + `docs/`-Scan (Repo).
- **Meldungen:** *Waisen abwärts* (Idee ohne `C-NNN`, Konzept ohne Spec, Spec ohne Item/Test) ·
  *Waisen aufwärts* (Spec/Code ohne Konzept-/Ideen-Herkunft — typisch nach Code-first; Input für
  `reconcile` Stufe 3) · *Widersprüche* (`superseded`-Idee noch referenziert, Spec zeigt auf
  gelöschten `C-NNN` u.ä.).
- `idea_status: parked | rejected` gilt als **bewusste Entscheidung**, nicht als Lücke — der Audit
  unterscheidet „vergessen" von „entschieden".
- **Output:** kompakter Ampel-Report je Kette (Terminal; dev-gui rendert ihn später, §6).

## 6. Architektur-Aufteilung (zwei Repos) + dev-gui-Schnittstelle

| Teil | Repo | Inhalt |
|---|---|---|
| **Pipeline-Logik** | `agent-flow` | Skill `/agent-flow:from-notes` (Ingest + `--sync`), Notiz-Reader, Fragenkatalog-Gate, `obsidian_source`-Profilfeld, Wiederverwendung von `requirement`/`architekt`/`dba` |
| **Button + Anzeige** | `dev-gui` | dritter Anlage-Weg „aus Obsidian-Notizen", Obsidian-Pfad in den Settings, Rendern + Beantworten des Fragenkatalogs (POST `/api/command`) |

**Schnittstelle, an der dev-gui andockt (Vertrag):**
- **Aufruf:** `/agent-flow:from-notes <ordnerpfad>` (Ingest) bzw. `/agent-flow:from-notes --sync` (Re-Sync; Ordner
  aus `obsidian_source`) — dünner Button → POST `/api/command`, exakt wie „Board abarbeiten"/„Änderung erfassen".
- **Fragenkatalog-Rückgabeformat:** **maschinenlesbar, definiert**, pro Frage mindestens
  `{ stage: a|b|c|sync, id, frage, quelle (Notiz-/Doku-Fundstelle), optional optionen[] }`. dev-gui rendert ihn
  und reicht die Antworten zurück; im Terminal-Pfad wird derselbe Katalog interaktiv gestellt (`AskUserQuestion`).
  Das exakte Format ist Teil der Spec (`docs/specs/obsidian-ingest.md`), damit dev-gui **ohne** Änderung an
  agent-flow andockt.

## 7. Touchpoints

- **`/agent-flow:from-notes`** (neu) — orchestriert die drei Stufen + den `--sync`-Modus; einziger Schreiber der
  Doc-/Board-Änderungen dieses Flusses (Commit pro Stufe).
- **`requirement`** — Stufe c (Spec→Board) läuft über den bestehenden Agenten (kein zweiter Zerlege-Pfad);
  außerdem Quelle des Fragenkatalog-Musters (Runden gezielter Fragen).
- **`architekt` / `dba`** — Stufe b bei tiefem Architektur-/Datenmodell-Detail.
- **`.claude/profile.md`** — neues additives Feld `obsidian_source` (wiederholbare Quelle, §4).
- **`templates/_docs/`** — Stufe a/b schreiben in dieselben durable Skelette (`concept.md`, `specs/_template.md`).
- **CONCEPT §4a/§4d** — dieses Subsystem ist ein **dritter Front-Door** in denselben durable-Docs-Pfad.
- **`reconcile-subsystem.md`** — bewusste Abgrenzung (§5): Re-Sync ist eigener Modus, kein Reconcile-Stufe-0.
  **Neu (07.07.2026):** Reconcile erhält eine **Stufe 3 (Obsidian-Rückspielung)**, die Konzept-Änderungen in die
  generierte Zone der Ideennotizen zurückspielt (dort spezifiziert) — sie nutzt die hier definierten Zonen (§4b)
  und IDs (`idea_id`/`C-NNN`).
- **`traceability-subsystem.md`** — der `--audit`-Modus (§5a) verlängert dessen Kette nach oben bis `IDEA-NNN`.

## 8. Bewusst NICHT

- **Kein Blind-Overwrite aus Notizen** — der Re-Sync überschreibt Konzept/Spec **nie automatisch** (§5); jede
  Divergenz ist ein User-Entscheid. (Genau der Unterschied zu Reconcile.)
- **Kein Schreiben ausserhalb der definierten Zonen** — nur Frontmatter-Sync-Felder + generierter Abschnitt
  (§4b); die persönliche Ausarbeitung wird nie berührt, gelöscht wird nie (`superseded` statt Löschen).
  *(Ersetzt 07.07.2026 das frühere Komplett-Verbot „Vault rein lesend" — das verhinderte den Kreislauf.)*
- **Kein zweiter Zerlege-Pfad** — Stufe c nutzt den bestehenden `requirement`-Agenten, dupliziert seine Slicing-/
  Schätz-Logik nicht.
- **Kein Ersatz der vagen Anforderung** — die Notiz-Pipeline ist additiv (dritter Weg), `requirement` bleibt.
- **Kein Einzel-Nachfragen pro Unklarheit** — pro Stufe **ein** gesammelter Katalog, am Stück beantwortet.
- **Kein dev-gui-Button in diesem Repo** — Cross-Repo (§6); agent-flow stellt nur Befehl + Rückgabeformat bereit.
- **Kein `/flow`-Start / kein Merge/Deploy** — die Pipeline schreibt nur durable Docs + Board-Items (To Do).
