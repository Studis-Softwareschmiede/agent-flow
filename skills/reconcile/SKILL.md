---
name: reconcile
description: Startet /agent-flow:reconcile — bringt die docs/ eines Projekts wieder mit der Realität in Deckung (rückwärtige Aufholung, Gegenstück zur vorwärtigen Drift-Disziplin). Stufe 1 (Form, läuft IMMER) hebt jede Spec mit veraltetem/fehlendem spec_format-Stempel automatisch auf die aktuelle Vorlage. Stufe 2 (Inhalt, nur bei leerem Kanban) lässt reviewer im Audit-Modus die Inhalts-Drift zwischen Code und Doku (concept/architecture/specs) ermitteln und zieht die Doku automatisch nach (Code ist maßgebend, kein Einzel-Nachfragen). Beide Stufen liefern zusammen genau EINEN PR zur Freigabe (AC13) — unabhängig von merge_policy; ohne Remote/Auth: committeter lokaler Branch bzw. Working-Tree-Diff als Fallback (AC14); bei reinem No-Op ohne Änderungen entsteht kein PR (AC15). Jeder Lauf protokolliert genau EINEN Block in docs/spec-audit.md — mit Dokument-Zeilen bei Änderungen, oder als expliziter --no-op-Block mit kanonischer "keine Änderung nötig"-Zeile, wenn weder Stufe 1 noch Stufe 2 etwas geändert haben (kein Lauf bleibt unprotokolliert). Stufe 3 (Obsidian-Rückspielung, nur bei gesetztem profile.obsidian_source) schliesst den Kreislauf Idee->Konzept->Spec->Code->Idee: Änderungen mit konzeptioneller Tragweite (C-NNN-Abschnitte) werden als Vault-Patch-Plan für die generierte Zone der verankerten Ideennotizen vorbereitet (Drei-Wege-Abgleich via last_sync/sync_hash, Konflikt IMMER an den Menschen, nie löschen — superseded); der Plan wird im PR protokolliert (docs/obsidian-patch-plan.md + PR-Body) und erst NACH dem Merge via --apply-vault ausgeführt (Mensch-Gate wirkt auch für den Vault). Kein eigener reconcile-Agent — Orchestrierung lebt komplett in diesem Skill. Aufruf: /agent-flow:reconcile [--apply-vault].
---

# /agent-flow:reconcile [--apply-vault]

Bringt die `docs/` des **aktuellen** Projekt-Repos (cwd) wieder mit der Realität in Deckung — on-demand, in drei Stufen. **Dieser Skill ist der einzige Schreiber** der Reconcile-Änderungen; es gibt **keinen** separaten `reconcile`-Agent (Vertrag `docs/architecture/reconcile-subsystem.md` §7, Spec `docs/specs/reconcile.md` AC1).

Bindende Quellen: `docs/specs/reconcile.md` (AC1–AC21) + `docs/architecture/reconcile-subsystem.md` (FINAL, §3 Stufe 3) + `docs/architecture/obsidian-ingest-subsystem.md` §4b (Vault-Schreibzonen). **Dieser Skill implementiert Stufe 1 (AC1–AC5), Stufe 2 (AC6–AC9, Inhalts-Abgleich) UND Stufe 3 (AC16–AC21, Obsidian-Rückspielung) vollständig.** Beide Stufen laufen in **derselben** Session; das Ergebnis (falls beide oder nur eine Stufe Änderungen erzeugt) wird **gemeinsam** als **ein** PR vorgelegt (§5) — **immer**, unabhängig von der Projekt-`merge_policy` (auch bei `direct`, AC13/AC14/AC15) — und **ein** Logbuch-Block geschrieben (§4) — „Pro Lauf ein Block" (AC10) bezieht sich auf den **gesamten** Reconcile-Lauf, nicht auf die einzelne Stufe. **Jeder** Lauf schreibt genau diesen einen Block — auch wenn weder Stufe 1 noch Stufe 2 noch Stufe 3 etwas geändert haben (No-Op, AC12): dann trägt der Block die kanonische „keine Änderung nötig"-Zeile statt Dokument-Zeilen (§4).

## 0. Setup
- **`--apply-vault`-Token** zuerst herausparsen: ist es gesetzt, läuft NUR §3e (nachgelagerte Vault-Patch-Ausführung nach gemergtem Reconcile-PR) — keine Stufen 1–3, kein neuer PR.
- `.claude/profile.md` lesen → `default_branch`, `obsidian_source` (falls gesetzt — steuert Stufe 3, AC16). `merge_policy` verzweigt die Freigabe **nicht mehr** (AC13) — reconcile landet immer als PR, egal ob das Projekt `pr` oder `direct` fährt.
- Auth **immer** sicherstellen — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-gh-auth.sh"` (unabhängig von `merge_policy`, da immer ein PR folgt, AC13). Schlägt das fehl: Stufe 1/2 laufen trotzdem unverändert weiter — der Fallback greift erst in §5 beim tatsächlichen PR-Öffnen (AC14).
- `git status` — Working-Tree sollte sauber sein, bevor Stufe 1 schreibt (sonst vermischen sich fremde Änderungen mit dem Reconcile-Diff). Ist der Tree nicht sauber: Hinweis ausgeben, User entscheiden lassen, ob fortgefahren wird.

## 1. Stufe 1 (Form) — läuft IMMER (AC2)
Rein doku-intern (kein Code-Bezug) — läuft unabhängig vom Board-Zustand, auch bei vollem Kanban.

### 1a. Erkennung (AC3)
```
bash scripts/reconcile-stage1-detect.sh
```
Liefert pro Zeile TAB-getrennt: `<pfad>  <missing|outdated>  <aktueller-wert>  <ziel-wert>` für jede Spec unter `docs/specs/`, deren `spec_format` vom aktuellen Vorlagenwert (`templates/_docs/specs/_template.md`) abweicht oder ganz fehlt. Eine leere Ausgabe heißt: **keine Form-Drift** → Stufe 1 erzeugt keinen Diff, keinen Logbuch-Block (AC2/E2-Prinzip) — weiter zu §2.

### 1b. Konvertierung je gefundener Spec (AC4)
Für jede vom Detect-Schritt gemeldete Spec, **einzeln und isoliert** (E1 — ein Fehlschlag darf den Gesamtlauf nicht stoppen):

1. **Original lesen** (`Read`) — vollständiger Inhalt, inkl. Frontmatter.
2. **Restrukturieren** — die Skill-Session selbst ist hier "der konvertierende Agent" aus dem Vertrag (§6) — kein Task-Dispatch, keine neue `agents/`-Datei. Inhalt **verlustfrei** in die Abschnitts-Struktur der aktuellen Vorlage (`templates/_docs/specs/_template.md`) überführen:
   - Frontmatter: `id`/`title`/`status`/`version` unverändert übernehmen; `spec_format` auf den Vorlagenwert **neu stempeln**.
   - Bestehende Abschnitte auf die nächstliegende Vorlagen-Überschrift mappen (`## Zweck`, `## Main Success Scenario` *(optional, nur falls im Original vorhanden oder sinnvoll ableitbar)*, `## Alternative Flows` *(optional)*, `## Acceptance-Kriterien`, `## Verträge`, `## Edge-Cases & Fehlerverhalten`, `## NFRs`, `## Nicht-Ziele`, `## Abhängigkeiten`). Inhalt, der keiner Vorlagen-Überschrift sauber zuzuordnen ist, wird unter der inhaltlich nächsten Überschrift **angehängt** statt verworfen (lossless-first, kein hübsches Wegkürzen).
   - **AC-Nummern bleiben stabil** (Vorlage: „AC-IDs sind stabil — nicht umnummerieren"). Reine Format-/Reihenfolge-Anpassung, **keine** inhaltliche Umdeutung der Kriterien.
3. **Schreiben** (`Write`/`Edit`) — derselbe Pfad, restrukturierter Inhalt.
4. **Verifizieren** (Pflicht vor Übernahme — Lossless-Garantie mechanisch absichern):
   - `spec_format` der neu geschriebenen Datei == Vorlagenwert (erneuter Lauf von `reconcile-stage1-detect.sh` meldet die Datei NICHT mehr).
   - Pflicht-Abschnitte vorhanden: `## Zweck`, `## Acceptance-Kriterien`, `## Verträge`, `## Edge-Cases & Fehlerverhalten`, `## Nicht-Ziele`, `## Abhängigkeiten`.
   - **AC-Mengen-Gleichheit:** die Menge der `AC<n>`-Token im Original == die Menge im konvertierten Text (`grep -oE 'AC[0-9]+'`, als Set vergleichen) — keine AC verloren, keine erfunden.
   - **Grobe Inhalts-Untergrenze:** Zeichenzahl der konvertierten Datei ≥ 60 % der Original-Zeichenzahl (Heuristik gegen versehentliches Abschneiden; stilistisches Straffen ist erlaubt, Halbieren-oder-mehr ist verdächtig).
5. **Bei Verifikations-Fehlschlag (E1):** `git checkout -- <pfad>` (Revert auf Original — die Spec bleibt unverändert), die Spec auf die **Nicht-konvertiert-Liste** für den Skill-Output/PR-Bericht setzen, **weiter** mit der nächsten Spec (kein Abbruch des Gesamtlaufs).
6. **Bei Erfolg:** Pfad + Ziel-Version auf die **Konvertiert-Liste** setzen (für §1c/Logbuch).

### 1c. Logbuch-Zeilen sammeln (AC5/AC10/AC11) — Schreiben erfolgt gebündelt in §4
Für jede **tatsächlich konvertierte** Spec (AC11 — „Block enthält nur die getroffenen Änderungen"; nicht-konvertierte Specs sind **keine** Änderung und erscheinen **nicht** im Logbuch, sondern nur im PR-/Skill-Bericht, s. §1b.5) **eine** Zeile auf die **Stufe-1-Logbuch-Liste** sammeln:
```
Spec <pfad> auf <ziel-version> konvertiert
```
Diese Liste wird **nicht** sofort geschrieben — `scripts/spec-audit-append.sh` wird erst **einmal** in §4 aufgerufen, zusammen mit den Stufe-2-Zeilen aus §2d und den Stufe-3-Zeilen aus §3d (AC10: „Pro Lauf **ein** Block" — bezieht sich auf den gesamten Reconcile-Lauf, nicht je Stufe einzeln getrennt geschrieben). Ist die Stufe-1-Konvertiert-Liste leer, trägt Stufe 1 einfach nichts zur gemeinsamen Liste bei (kein leerer Beitrag).

## 2. Stufe 2 (Inhalt) — NUR bei leerem Kanban (AC6–AC9)

### 2a. Vorbedingungs-Check (AC6, hart) — graceful bei fehlendem Board
```
bash scripts/reconcile-stage2-gate.sh
```
Liefert auf stdout **genau ein** Token (Details/Spaltenzahlen auf stderr, nur informativ):

- **`empty`** — alle vier Spalten (`To Do`/`In Progress`/`Blocked`/`In Review`) leer → Vorbedingung erfüllt, **weiter mit §2b**.
- **`not-empty`** — mindestens eine Spalte belegt → **Stufe 2 übersprungen**, Ausgabe „Stufe 2 übersprungen — erst Board leerräumen" (AC6/A1). Kein Audit-Dispatch, kein Doku-Nachzug. Weiter mit §3 (Stufe 3) bzw. §4.
- **`no-board`** — das Board-Skelett fehlt (kein `board.yaml`) → die Vorbedingung ist **nicht prüfbar**; das Skript bricht dafür **nicht** hart ab (Review-Lehre S-011: `scripts/board` würde für schreibende Verben hart abbrechen — coder/L15 verlangt für lesende Prüfungen graceful Handling). Ausgabe „Stufe 2 übersprungen — kein Board-Skelett vorhanden, Vorbedingung nicht prüfbar" und **konservativ überspringen** (NFR „Vorsicht" — kein impliziter Inhalts-Abgleich, wenn nicht feststeht, ob noch etwas offen ist). Weiter mit §3 bzw. §4.

Das Skript selbst terminiert in allen drei Fällen mit Exit 0 (reine Lese-/Report-Operation) — ein Exit ≠ 0 bedeutet ein echtes Aufrufproblem (z.B. `scripts/board` selbst defekt) und muss dem User gemeldet werden, ohne den Lauf vorzutäuschen.

### 2b. Erkennen — `reviewer` im Audit-Modus, Reconcile-Variante (AC7)
**Nur wenn §2a `empty` ergeben hat.** Dispatch (Task) des `reviewer`-Agenten im **Audit-Modus, Reconcile-Variante** (`agents/reviewer.md` „Audit-Modus — Reconcile-Variante"):

- **Input:** der Bestand des Projekt-Repos (kein Diff). Vergleichsbasis: `concept.md`/`CONCEPT.md` + `architecture.md`/`docs/architecture/*.md` + `docs/specs/*.md` gegen das **beobachtbare Verhalten im Code**. (Standard-Pfade laut Vorlage: `docs/concept.md` + `docs/architecture.md`; führt das Projekt stattdessen einen Root-`CONCEPT.md` und/oder mehrere `docs/architecture/*.md`-Subsystem-Verträge — wie dieses Repo selbst — gelten dessen tatsächliche Doku-Dateien als Vergleichsbasis.)
- **Drift-Heuristik = identisch zum Drift-Gate** (Endpunkte/UI/I-O/Fehler-Statuscodes/Datenfelder/NFR-Limits; reiner Refactor zählt **nicht**).
- **Output:** priorisierter Fund-Report, **je Fund**: `file:line` (Code-Fundstelle) + betroffenes Doku-Dokument + **Richtungsvorschlag** (konkrete Ziel-Formulierung für die Doku-Stelle). **Kein** Gate, **keine** Board-Items — reiner Bericht.
- Leerer Report (keine Drift) → **weiter mit §3 bzw. §4 ohne Stufe-2-Beitrag** (A2/E2 — kein Rauschen).

### 2c. Nachziehen — Code ist maßgebend (AC8)
**Nur wenn §2b mindestens einen Fund geliefert hat.** Für **jeden** Fund, **automatisch und ohne Einzel-Nachfragen** (AC8 — „kein per-Drift-Prompt", der Mensch-Gate ist der finale Diff-Blick in §5, nicht eine Entscheidung je Fund):

1. **Existiert das betroffene Dokument:** `Read` (voller Inhalt) → `Edit` die betroffene Stelle entsprechend dem Richtungsvorschlag des `reviewer`-Funds. Code-Verhalten wird **wörtlich/inhaltlich** übernommen — keine eigene Interpretation über den Fund hinaus.
2. **Fehlt das Dokument komplett** (der Fund meldet „Dokument fehlt"): **dieselbe Layout-Erkennung wie in §2b** anwenden, BEVOR `Write` aufgerufen wird — kein blindes Anlegen der kanonischen Einzeldatei, wenn das Projekt bereits ein abweichendes Muster etabliert hat (coder/L27):
   - **Architektur:** `bash scripts/reconcile-doc-layout.sh architecture` ausführen. Liefert `multi` → existiert bereits ein `docs/architecture/`-Verzeichnis mit mindestens einer `*.md`-Subsystem-Datei (wie dieses Repo selbst) → neue Datei unter `docs/architecture/<subsystem>.md` anlegen (Subsystem-Name aus dem Fund-Kontext ableiten — Feature-/Komponentenname des Funds). Liefert `single` → kanonische Einzeldatei `docs/architecture.md` aus `templates/_docs/architecture.md` anlegen.
   - **Konzept:** `bash scripts/reconcile-doc-layout.sh concept` ausführen. Liefert `root` → existiert bereits ein Root-`CONCEPT.md` (wie dieses Repo) → dort die betroffene Sektion ergänzen statt einer neuen `docs/concept.md`. Liefert `canonical` → kanonisch `docs/concept.md` aus `templates/_docs/concept.md` anlegen.
   - **Spec:** unverändert `docs/specs/<feature>.md` aus `templates/_docs/specs/_template.md` (Specs sind bereits 1:1 pro Feature — keine Layout-Variante, `reconcile-doc-layout.sh` kennt diesen Typ nicht).
   In allen Fällen: gefüllt mit dem im Fund beschriebenen, beobachteten Verhalten. Kurz: derselbe Layout-Entscheid wie im Lese-/Vergleichspfad (§2b — „dessen tatsächliche Doku-Dateien als Vergleichsbasis") gilt symmetrisch für den Schreibpfad.
3. Jedes tatsächlich geänderte/neu angelegte Dokument auf die **Stufe-2-Logbuch-Liste** sammeln (§2d) — **ein** Eintrag pro Dokument (nicht pro Einzel-Fund, falls mehrere Funde dasselbe Dokument betreffen).

### 2d. Logbuch-Zeilen sammeln (AC9/AC10/AC11) — Schreiben erfolgt gebündelt in §4
Für jedes in §2c tatsächlich berührte Dokument **eine** Zeile auf die **Stufe-2-Logbuch-Liste**:
```
Konzept <pfad> nachgezogen        (bestehendes Dokument geändert)
Architektur <pfad> nachgezogen    (bestehendes Dokument geändert)
Spec <pfad> nachgezogen           (bestehendes Dokument geändert)
Spec <pfad> neu angelegt          (Dokument existierte nicht)
```
Wie bei §1c wird hier **noch nicht** geschrieben — siehe §4.

## 3. Stufe 3 (Obsidian-Rückspielung) — NUR bei gesetztem `obsidian_source` (AC16–AC21)

Schliesst den Kreislauf **Idee → Konzept → Spec → Code → zurück zur Idee**. Läuft nach Stufe 2. **Wichtig:** Stufe 3 schreibt in diesem Lauf **nichts** in den Vault — sie erstellt nur den **Patch-Plan**; die Ausführung folgt erst **nach** dem Merge (§3e, AC21).

### 3a. Vorbedingung (AC16) — graceful Skip
Ist `profile.obsidian_source` **nicht** gesetzt **oder** der Ordner nicht erreichbar/lesbar → Stufe 3 **überspringen** mit klarem Hinweis („kein Notiz-Ordner am Projekt vermerkt" bzw. „Vault nicht erreichbar"); Stufen 1+2 und der restliche Lauf bleiben unberührt — kein Regress für Projekte ohne Vault-Anbindung. *(deckt A3)*

### 3b. Kandidaten ermitteln — nur konzeptionelle Tragweite (AC17)
1. **Konzept-Delta:** die in diesem Lauf (Stufe 2) und seit dem letzten Rückspiel-Stand geänderten/neuen/`superseded`-markierten **`C-NNN`-Abschnitte** in `docs/concept.md` bestimmen (Diff gegen `default_branch` bzw. gegen die `last_sync`-Stände der verankerten Notizen). Reine Spec-/Verhaltensänderungen ohne `C-NNN`-Bezug enden bei Stufe 2 und erreichen den Vault **nicht**.
2. **Verankerung auflösen:** je betroffener `C-NNN` die zugehörige Ideennotiz über deren Frontmatter (`c_refs` enthält `C-NNN` bzw. `(← IDEA-NNN)`-Herkunft im Konzept) finden — Frontmatter-Scan aller `.md` unter `obsidian_source`.
3. **Waisen aufwärts (AC19):** `C-NNN`-Abschnitte/Specs **ohne** Ideen-Herkunft (Erkennungslogik identisch zu `from-notes --audit`, dort §6.2) → für jede Waise eine **neue Ideennotiz** in den Plan aufnehmen: Pfad im `obsidian_source`-Ordner, `idea_id` (nächste freie `IDEA-NNN`), `idea_status: adopted`, Herkunftsvermerk `(← C-NNN)`, Inhalt **nur** in der generierten Zone `## Stand aus Konzept (generiert)` — klar als repo-first gekennzeichnet.

### 3c. Drei-Wege-Abgleich + Patch-Plan (AC18/AC20)
Je verankerter Ideennotiz über `last_sync`/`sync_hash` klassifizieren:
- **nur Repo geändert** (Notiz-Hash == `sync_hash`, Konzept seit `last_sync` geändert) → **Patch geplant:** generierten Abschnitt `## Stand aus Konzept (generiert)` mit dem aktuellen `C-NNN`-Stand ersetzen (Patch, **nie** Datei-Überschreiben) + Sync-Felder neu stempeln. Überholtes → `idea_status: superseded` — **nie** löschen (AC18).
- **nur Obsidian geändert** (Notiz-Hash != `sync_hash`, Konzept unverändert) → **kein** Patch; als „Kandidat für `from-notes --sync`" vermerken (dessen Autorität bleibt unangetastet).
- **beide geändert** → **Konflikt**: als `konflikt-offen` in den Plan (Notiz + betroffene `C-NNN` + beide Stände benannt) — wird **nie** automatisch entschieden; der Mensch löst ihn im PR-Review bzw. via `--sync` (AC20). Repo-intern bleibt „Code gewinnt" (AC8) — es endet an der Repo-Grenze.

**Plan persistieren:** alle geplanten Patches nach **`docs/obsidian-patch-plan.md`** schreiben (Kopf: Datum + Lauf; je Eintrag: `notiz-pfad · zone (generiert|frontmatter) · art (rückspielung|neue-notiz|superseded-stempel|konflikt-offen) · c_refs · kurzbeschreibung`). Diese Datei fährt im Reconcile-Commit/PR mit (§5) — sie IST das Review-Artefakt für den Vault-Teil (AC21). Ziel-Zonen sind **strikt** die aus `obsidian-ingest-subsystem.md` §4b — persönliche Ausarbeitung wird nie berührt.

### 3d. Logbuch-Zeilen sammeln (Schreiben gebündelt in §4)
Je Plan-Eintrag eine Zeile („Ideennotiz X: Rückspielung geplant" / „neue Ideennotiz Y geplant (← C-NNN)" / „Ideennotiz Z: Konflikt offen"). Kein Plan-Eintrag → keine Stufe-3-Zeilen.

### 3e. Nachgelagerte Ausführung — `/agent-flow:reconcile --apply-vault` (AC21)
Läuft als **eigener Aufruf nach dem Merge** des Reconcile-PRs (Mensch-Gate ist damit auch für den Vault wirksam):
1. **Guard:** cwd auf `default_branch` + `docs/obsidian-patch-plan.md` vorhanden und committet (= gemergt). Fehlt beides → klarer Abbruch („kein gemergter Patch-Plan — nichts auszuführen").
2. **Ausführen:** jeden Plan-Eintrag **ausser** `konflikt-offen` umsetzen — ausschließlich generierte Zone patchen / neue gekennzeichnete Notiz anlegen / Frontmatter-Sync-Felder stempeln (`last_sync`, `sync_hash` neu; Zonen strikt nach §4b). `konflikt-offen`-Einträge werden ausgegeben, **nicht** ausgeführt.
3. **Abschluss:** ausgeführte Einträge aus `docs/obsidian-patch-plan.md` entfernen (Datei bei leerem Plan auf einen „ausgeführt am <Datum>"-Kopf reduzieren) und diesen Abbau als kleinen Direkt-Commit auf `default_branch` landen (reiner Buchhaltungs-Commit; scheitert Push wegen Branch-Protection → docs-only-PR + Self-Merge, analog `from-notes`). Der Vault selbst wird **nie** committet.

## 4. Logbuch — EIN Block für den gesamten Lauf, IMMER (AC5/AC9/AC10/AC11/AC12)
Kombiniere die Stufe-1-Liste (§1c), die Stufe-2-Liste (§2d) und die Stufe-3-Liste (§3d) zu **einer** Zeilenmenge (Stufe-1-Zeilen zuerst, dann Stufe 2, dann Stufe 3 — feste, nachvollziehbare Reihenfolge).

**Hat die kombinierte Liste ≥ 1 Zeile** (mindestens Stufe 1 oder Stufe 2 hat etwas geändert), rufe **einmal** auf:
```
scripts/spec-audit-append.sh \
  "<Stufe-1-Zeile-1>" … \
  "<Stufe-2-Zeile-1>" …
```

**Ist die kombinierte Liste leer** (weder Stufe 1 noch Stufe 2 noch Stufe 3 hatten etwas zu protokollieren — der reine No-Op-Fall), rufe **stattdessen** den expliziten No-Op-Modus auf:
```
scripts/spec-audit-append.sh --no-op
```
Das schreibt einen validen Block mit **genau einer** kanonischen „keine Änderung nötig"-Zeile (AC12) — **niemals** wird `spec-audit-append.sh` ganz ausgelassen. Jeder Reconcile-Lauf hinterlässt so **immer** genau einen Logbuch-Block, egal ob mit Änderungs-Zeilen oder als No-Op (AC10/AC12) — „gelaufen, nichts nötig" bleibt von „nie gelaufen" unterscheidbar.

## 5. Freigabe — EIN PR für den gesamten Lauf, IMMER (AC1/AC5/AC9/AC13/AC14/AC15/AC21)

**Kein-PR-Guard zuerst (AC15/AC21 — kein leerer No-Op-PR):** Haben **weder** §1b **noch** §2c mindestens eine Datei tatsächlich geändert/angelegt **und** steht **kein** Vault-Patch im Plan (§3c leer), entsteht **kein** PR und **kein** Branch — der Lauf endet hier mit „keine Drift — kein PR" (der `--no-op`-Block aus §4 bleibt als reiner Working-Tree-Eintrag stehen, AC12 bleibt davon unberührt). Ein Lauf, dessen **einzige** Änderung der Vault-Patch-Plan ist, erzeugt **dennoch** einen PR — der Plan ist das Review-Artefakt (AC21).

Reconcile landet sein Gesamt-Ergebnis **immer** als **ein** PR — **unabhängig** von `merge_policy` (auch bei `direct`, AC13). Der frühere `merge_policy: direct`-Sonderfall (unstaged Working-Tree-Diff, kein Commit) entfällt für reconcile ersatzlos.

1. **Branch + Commit:** neuer Branch `reconcile/<YYYY-MM-DD>` ab `default_branch` (`git checkout -b reconcile/<YYYY-MM-DD> <default_branch>`; existiert der Branchname bereits — z.B. zweiter Lauf am selben Tag — Suffix `-2`, `-3`, … anhängen). **Ein** Commit mit **allen** berührten Dateien aus Stufe 1 + Stufe 2 + ggf. dem Vault-Patch-Plan `docs/obsidian-patch-plan.md` (§3c) + dem `docs/spec-audit.md`-Block (`git add docs/specs/<konvertierte-pfade> <stufe-2-pfade> docs/obsidian-patch-plan.md docs/spec-audit.md && git commit -m "..."`).
   - **Scheitert bereits Branchen/Committen** (z.B. Working-Tree-Konflikt) → Fallback **(b)** unten: Änderungen bleiben als reiner Working-Tree-Diff erhalten.
2. **Push:** `git push -u origin reconcile/<YYYY-MM-DD>`.
   - **Scheitert der Push** (kein Remote konfiguriert, `gh`-Auth aus §0 fehlgeschlagen, Push abgelehnt) → Fallback **(a)** unten: der committete lokale Branch bleibt erhalten.
3. **PR:** `gh pr create` gegen `default_branch` mit Body: Liste der Stufe-1-Konvertierungen (alt-Version → neu-Version) + ggf. Nicht-konvertiert-Liste (§1b.5) + Liste der Stufe-2-Nachzieh-Änderungen (Fund → Doku-Stelle) + **Vault-Patch-Plan** (AC21: je Patch Notiz · Zone · Art — Rückspielung / neue Notiz / superseded-Stempel / Konflikt-offen; Hinweis „Ausführung nach Merge via `/agent-flow:reconcile --apply-vault`"). **Kein Self-Merge** — Freigabe ist ausschließlich Mensch-Gate (analog `train`/`retro`-PR-Mechanik).

**Fallback ohne Remote/Auth (AC14) — kein stiller Fehlschlag, kein Datenverlust:**
- **(a) Branch + Commit gelungen, Push/PR gescheitert:** der committete lokale Branch `reconcile/<YYYY-MM-DD>` bleibt erhalten (kein Rollback). Ausgabe: klare Meldung *warum* kein PR entstand (kein Remote konfiguriert / `gh`-Auth fehlgeschlagen / Push abgelehnt) **und** *wie der Mensch nachzieht* (Remote setzen bzw. `bash scripts/ensure-gh-auth.sh` prüfen, dann `git push -u origin reconcile/<YYYY-MM-DD>` und `gh pr create` manuell ausführen).
- **(b) schon Branchen/Committen gescheitert:** die Änderungen (Stufe 1 + Stufe 2) bleiben unstaged im Working-Tree als reiner Diff erhalten (`git diff`). Ausgabe: klare Meldung + Hinweis, dass der User den Diff selbst prüft/committet/branched.
- In beiden Fällen endet der Lauf mit **definiertem** Status — nie mit einem stillschweigend verschluckten Fehler.

## Output
```
Stufe 1: <N> Spec(s) konvertiert, <M> nicht-konvertiert (E1)
  Konvertiert: <pfad> (<alt> -> <neu>), …
  Nicht-konvertiert: <pfad> (<grund>), …
Stufe 2: <übersprungen — Board nicht leer | übersprungen — kein Board-Skelett | <K> Dokument(e) nachgezogen | keine Inhalts-Drift gefunden>
  Nachgezogen: <pfad> (<Fund-Kurzbeschreibung>), …
Stufe 3: <übersprungen — kein obsidian_source | übersprungen — Vault nicht erreichbar | <P> Vault-Patch(es) geplant (docs/obsidian-patch-plan.md, Ausführung nach Merge via --apply-vault) | nichts zurückzuspielen>
  Geplant: <notiz> (<rückspielung|neue-notiz|superseded|konflikt-offen>), …
Diff: <PR-Link | "Kein PR — Fallback: committeter lokaler Branch reconcile/<YYYY-MM-DD> (Grund: <kein Remote|Auth fehlgeschlagen|Push abgelehnt>; Nachziehen: <Remote setzen bzw. Auth prüfen, dann push+PR manuell>)" | "Kein PR — Fallback: Working-Tree-Diff, nicht committet (Grund: <Branchen/Committen gescheitert>; Nachziehen: Diff selbst prüfen/committen)" | "keine Drift — kein PR">
```

## Grenzen (HART)
- Editiert **ausschließlich** Doku: `docs/specs/*.md` (Stufe 1 + Stufe 2), `concept.md`/`CONCEPT.md`, `architecture.md`/`docs/architecture/*.md` (Stufe 2), `docs/obsidian-patch-plan.md` (Stufe 3) + `docs/spec-audit.md` (Logbuch) — **kein** App-Code, **keine** Board-Status-Änderung.
- **Vault nur nach Merge + nur in Zonen (AC18/AC21):** der Reconcile-Lauf selbst schreibt **nie** in den Vault — nur der Plan wird erstellt; `--apply-vault` (erst nach gemergtem Plan) schreibt ausschließlich generierte Zone + Frontmatter-Sync-Felder, löscht **nie** (`superseded`), führt `konflikt-offen` **nie** automatisch aus (AC20). Der Vault wird **nie** ge-`add`et/committet.
- **Kein** eigener `reconcile`-Agent. **Kein** Task-Dispatch für das Schreiben der Konvertierung (Stufe 1) oder des Nachzugs (Stufe 2) — die Skill-Session restrukturiert/schreibt selbst (AC1, Vertrag §7). Der **einzige** Task-Dispatch ist der `reviewer`-Audit-Dispatch in §2b (reines **Erkennen**, kein Schreiben).
- **Kein** Self-Merge des eigenen PRs — immer Mensch-Gate, unabhängig von `merge_policy` (AC13).
- Stufe 2 läuft **ausschließlich** bei `empty` aus §2a (AC6, hart) — bei `not-empty` oder `no-board` **kein** Audit-Dispatch, **kein** Doku-Nachzug.
- **Kein** Einzel-Nachfragen pro Drift-Fund (AC8) — der Mensch-Gate ist ausschließlich der finale Diff-Blick in §5.
