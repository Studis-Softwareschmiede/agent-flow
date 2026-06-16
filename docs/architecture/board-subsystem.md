# Board-Subsystem — Konzept (Feature → Story, ohne GitHub)

> Status: **Konzept / Entwurf** — kein Code geändert. Dieses Dokument beschreibt die
> Ablösung der GitHub-Projects-v2-Boards durch ein eigenes, zweistufiges Board
> (Feature → Story), dessen Quelle der Wahrheit git-versionierte Dateien im
> Projekt-Repo sind, und das `dev-gui` zu einer fabrikweiten Übersicht aggregiert.
>
> Richtungsentscheidungen (vom Owner bestätigt, 2026-06-14):
> 1. **Source of Truth:** git-Dateien im jeweiligen Projekt-Repo (`board/`), nicht GitHub, keine zentrale DB.
> 2. **Reichweite:** zentrale, **projektübergreifende** Übersicht (Projekt → Feature → Story) — aggregiert aus den Repo-Dateien.
> 3. **Migration:** **direkter Schnitt (Big Bang)** weg von GitHub, mit einmaligem Export + git-Rückfallebene.

---

## 1. Warum

Heute legt die Fabrik **pro Projekt ein GitHub Project v2** an. Das Board ist
*flach*: nur Issues mit Status-Spalte (`To Do │ In Progress │ Blocked │ In Review │
Done`), Priority-Feld und Abhängigkeiten als Freitext (`depends: #n`) im Body.
`gh`-Befehle sind über `new-project`, `requirement`, `flow`, `adopt`, `cicd`
verstreut. Es gibt **keine** Feature-/Story-Hierarchie und keine
projektübergreifende Sicht.

Limitierungen, die wir auflösen wollen:

| Heute (GitHub) | Ziel (eigenes Board) |
|---|---|
| Flach: Issue = einzige Einheit | Zwei Ebenen: **Feature** gruppiert **Stories** |
| Status nur als Board-Spalte (nicht im git-Diff sichtbar) | Status als git-versioniertes Feld → Historie, Review, Offline |
| `depends:` als Freitext im Body | strukturierte, validierbare Referenzen (`parent`, `depends`) |
| Ein Board pro Projekt, keine Gesamtsicht | `dev-gui` aggregiert alle Repos zu **einer** Übersicht |
| `gh` verstreut über 5 Stellen | **eine** Board-Abstraktion (`board`-CLI), ein Schreiber |
| Externe Abhängigkeit (GitHub-API, PAT, Rate-Limits) | lokal, kostenlos, in jedem Klon vorhanden |

---

## 2. Zielbild in einem Bild

```
                          ┌──────────────────────────────────────────┐
                          │            dev-gui (Fabrik-GUI)            │
                          │   Zentrale Übersicht über ALLE Projekte    │
                          │   liest (read-only) + indiziert die Repos  │
                          └───────────────▲────────────────────────────┘
                                          │  scan / index (read-only)
        ┌─────────────────────────────────┼─────────────────────────────────┐
        │                                 │                                 │
┌───────┴────────┐               ┌────────┴───────┐               ┌─────────┴──────┐
│  Repo: dev-gui │               │ Repo: climate… │               │  Repo: …       │
│  board/        │               │  board/        │               │  board/        │
│   features/    │   = Source    │   features/    │               │   features/    │
│   stories/     │     of Truth  │   stories/     │               │   stories/     │
│  docs/specs/   │   (git)       │  docs/specs/   │               │  docs/specs/   │
└───────▲────────┘               └───────▲────────┘               └────────────────┘
        │ Read/Write (board-CLI)
        │
┌───────┴───────────────────────────────────────────────────────────────────────┐
│  Agents:  requirement (legt Feature+Stories an) │ flow (einziger Status-Schreiber)│
│           coder/reviewer/tester/cicd (lesen Story + Spec, schreiben KEINEN Status)│
└───────────────────────────────────────────────────────────────────────────────┘
```

**Kernidee:** Jedes Repo trägt sein Board als Dateien bei sich (`board/`). Die
Agents arbeiten lokal über eine **Board-Abstraktion** (`scripts/board` — CLI/Lib)
gegen diese Dateien. `dev-gui` macht aus den vielen `board/`-Ordnern *eine*
Live-Übersicht, indem es die Repos read-only scannt. **Geschrieben wird immer in
die Dateien** (git als Audit-Log), nie in eine separate zentrale DB.

---

## 3. Zwei Ebenen: Feature und Story

### Feature
Grobgranulare Roadmap-Einheit. Ein Feature bündelt fachlich zusammengehörige
Stories und trägt das *Was/Warum* (Ziel, Spec/Concept, Definition of Done auf
Feature-Ebene). Ein Feature wird **nicht direkt von `/flow` abgearbeitet** — es ist
die Klammer und liefert den Fortschritts-Rollup.

### Story
Die **ausführbare Arbeitseinheit** — exakt das, was `/flow` heute als „Item"
abarbeitet (coder → reviewer ⇄ tester → cicd → Done). Jede Story hat genau **ein**
Parent-Feature. Stories tragen die operativen Felder (Status, AC-Referenz,
Schätzung, Abhängigkeiten, PR-Link).

```
Feature  F-001  „Server-Provisioning"          (Roadmap-Ebene, Rollup)
  ├── Story  S-014  „IONOS-Adapter"             (← /flow arbeitet hier)
  ├── Story  S-015  „Cloud-Init-Template"
  └── Story  S-016  „Key-Assignment"
Feature  F-002  „Key-Rotation"
  ├── Story  S-031  …
  └── …
```

---

## 4. Datenmodell — Attribute (die grafische Darstellung)

### 4.1 Feature-Board — Attribute

```
╔══════════════════════════════════════════════════════════════════════════╗
║  FEATURE  (board/features/F-001-provisioning.yaml)                         ║
╠══════════════════════════════════════════════════════════════════════════╣
║  id            F-001                 ← stabil, projektweit eindeutig        ║
║  title         Server-Provisioning   ← Kurztitel                            ║
║  goal          1–3 Sätze: Was & Warum (fachliches Ziel)                     ║
║  status        Backlog │ Planned │ Active │ Done │ Archived                 ║
║  priority      P0 │ P1 │ P2 │ P3     ← Reihenfolge auf Roadmap-Ebene        ║
║  spec          docs/specs/provisioning.md   (optional, Feature-Concept)     ║
║  definition_of_done   Feature gilt fertig, wenn … (prüfbar, grob)          ║
║  labels        [infra, vps]          ← frei, fachlich                       ║
║  depends       [F-000]               ← andere Features (grobe Reihenfolge)  ║
║  owner         alex                  ← optional                            ║
║  ── abgeleitet / Rollup (nicht von Hand gepflegt) ──────────────────────── ║
║  stories       [S-014, S-015, S-016] ← Kinder (Rückverweis, generierbar)    ║
║  progress      2/3 done · 1 in progress   ← aus Story-Status berechnet      ║
║  ── Metadaten ──────────────────────────────────────────────────────────── ║
║  created_at / updated_at             ← Zeitstempel                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### 4.2 Story-Board — Attribute

```
╔══════════════════════════════════════════════════════════════════════════╗
║  STORY  (board/stories/S-014-ionos-adapter.yaml)                           ║
╠══════════════════════════════════════════════════════════════════════════╣
║  id            S-014                 ← stabil, projektweit eindeutig        ║
║  parent        F-001                 ← PFLICHT: genau ein Feature           ║
║  title         IONOS-Adapter                                                ║
║  status        To Do │ In Progress │ Blocked │ In Review │ Done             ║
║                                       ← einziger Schreiber: /flow           ║
║  priority      P0 │ P1 │ P2 │ P3     ← Reihenfolge innerhalb To-Do-Queue    ║
║  spec          docs/specs/provisioning.md   ← Source of Truth für AC        ║
║  implements    [AC1, AC2, AC4]       ← welche AC der Spec diese Story erfüllt║
║  depends       [S-013]               ← andere Stories (Reihenfolge-Gate)    ║
║  labels        [db, security, ui]    ← steuern Dispatch (z.B. db → dba)     ║
║  ── Dispo: Schätzung & Ist (vgl. metrics-subsystem · Detail §4.4) ──────── ║
║  size_est       S │ M │ L │ XL       ← /flow-Heuristik, Schätzbasis         ║
║  dispo_est      <ep|null> (+~tok)    ← S/M: Heuristik · L/XL: Schätz-Agent  ║
║  dispo_act      <ep|null> +~tok      ← ep_act + tok_total, beim Done        ║
║  dispo_forecast +/-% (est vs act)    ← abgeleitet, füttert retro-Baseline   ║
║  estimate_note  <text|null>          ← Begründung d. Schätz-Agenten (L/XL)  ║
║  ── Laufzeit-Verknüpfung ──────────────────────────────────────────────── ║
║  branch        feat/S-014-ionos      ← von /flow gesetzt                    ║
║  pr            <url|null>             ← bei pr-Policy                        ║
║  blocked_reason  <text|null>         ← Grund bei status=Blocked             ║
║  ── Metadaten ──────────────────────────────────────────────────────────── ║
║  created_at / updated_at / done_at                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### 4.3 Attribut-Vergleich auf einen Blick

| Attribut | Feature | Story | Bemerkung |
|---|:---:|:---:|---|
| `id` | ✅ `F-###` | ✅ `S-###` | projektweit eindeutig, stabil |
| `parent` | — | ✅ | Story → genau 1 Feature |
| `title` | ✅ | ✅ | |
| `goal` / `title`-Beschreibung | ✅ (goal) | — | Feature trägt das *Warum* |
| `status` | ✅ (5: Backlog…Archived) | ✅ (5: To Do…Done) | **unterschiedliche** Lebenszyklen |
| `priority` | ✅ Roadmap | ✅ Queue | gleiche Skala P0–P3 |
| `spec` | ✅ (optional) | ✅ (AC-Quelle) | Datei unter `docs/specs/` |
| `implements` (AC-Liste) | — | ✅ | Drift-Gate-Bindung |
| `definition_of_done` | ✅ grob | — | Story-Akzeptanz = AC in Spec |
| `depends` | ✅ (Features) | ✅ (Stories) | Reihenfolge-Gate |
| `labels` | ✅ fachlich | ✅ dispatch-steuernd | |
| `dispo_est`/`dispo_act` (EP + Tokens) | — | ✅ | „Dispo" — geschätzt vs. Ist, §4.4 |
| `size_est` / `estimate_note` | — | ✅ | Schätzbasis + Agenten-Begründung |
| `branch`/`pr`/`blocked_reason` | — | ✅ | Laufzeit |
| `stories`/`progress` (Rollup) | ✅ abgeleitet | — | aus Kind-Status berechnet |

> Faustregel: **Feature = Roadmap & Klammer (Was/Warum)**, **Story = ausführbare
> Einheit (Wie/Wann, von `/flow` getrieben)**. Akzeptanzkriterien leben wie heute
> in `docs/specs/` — Story referenziert sie über `spec` + `implements`.

### 4.4 „Dispo" — geschätzter vs. tatsächlicher Aufwand pro Story

**„Dispo" = Aufwand einer Story.** Einheit: **EP (Effort Points)** — die bereits
vorhandene, kalibrierbare Aufwands-Münze — **zusätzlich roh in Tokens** angezeigt.
**Kein Geldwert**: die Fabrik läuft über ein Abo, nicht über API-pro-Token; eine
CHF-Umrechnung ist bewusst out-of-scope (vgl. `frontier-cost-mode.md`).

Drei Werte je Story — alle stützen sich auf die **bestehende** Mess-Kette
(`metrics-subsystem`), nichts wird neu erfunden:

```
                 ┌─────────────────────────────────────────────────────────┐
  VORAB          │  dispo_est   = ep_est        (geschätzt, beim Eintritt)  │
  (Schätzung)    │              + ~tok-Erwartung (aus baseline-Median)       │
                 └───────────────────────────┬─────────────────────────────┘
                                              │  /flow arbeitet Story ab
                 ┌────────────────────────────▼────────────────────────────┐
  NACH ABSCHLUSS │  dispo_act   = ep_act        (EP-Formel beim Done)        │
  (Ist)          │              + tok_total      (token-collect, best-effort)│
                 └───────────────────────────┬─────────────────────────────┘
                                              │
                 ┌────────────────────────────▼────────────────────────────┐
  QS / KALIBR.   │  dispo_forecast = (est−act)/act   → retro aggregiert      │
  (retro)        │  → baseline.json: Mediane + EP-Gewichte + forecast_mae    │
                 │  → nächste Schätzung wird genauer (geschlossener Kreis)    │
                 └─────────────────────────────────────────────────────────┘
```

**Schätz-Mechanik (Hybrid):**
- **S/M** → deterministische Heuristik in `/flow` (AC-Zahl + Komponenten + Labels →
  `size_est` → `dispo_est` via `baseline.json`). **0 Zusatz-Token**, wie heute.
- **L/XL (oder on-demand)** → dedizierter **Schätz-Agent** `estimator` (spezifiziert
  in `docs/specs/estimator.md`, Agent: `agents/estimator.md`) liefert einen
  **begründeten Vorschlag**: `dispo_est` in EP + 1–2 Sätze in `estimate_note`
  (Komponenten, Risiken) + optional Split-Empfehlung. Er schätzt **relativ** gegen
  Referenz-Stories (kuratierte Anker in `knowledge/reference-stories.md` + ähnlichste
  abgeschlossene Stories aus `items.jsonl` als Few-shot) und verbessert sich über
  `retro` (Bias-Kalibrierung automatisch; Anker & Anweisung via PR+Gate). Token nur
  dort, wo Schätzen wirklich schwer ist.

**Ist-Erfassung** bleibt unverändert: `/flow` schreibt beim Done `ep_act` (EP-Formel)
und `tok_total` (best-effort aus den Subagent-Transcripts). **QS-Schritt** = der
`retro`-Agent (Modi C+D): er rechnet `est` gegen `act`, kalibriert EP-Gewichte und
Mediane neu und trackt die Prognosegüte (`forecast_mae`).

**ID-Brücke (wichtig für die Board-Ablösung):** Der Metrik-Schlüssel
`item` ist ein **`int`** (Board-Item-/Issue-Nummer, vgl. metrics-subsystem §2.1/§2.2).
`/flow` schreibt dafür den **numerischen Anteil der Story-ID** als `int` in
`dispatches.jsonl`/`items.jsonl` (`S-014` → `14`) — so bleibt der Typ `int` (Aggregation
braucht numerische Vergleiche) UND die Zuordnung zur Story **eindeutig** (`14 ↔ S-014`),
damit `dispo_est`/`dispo_act` der richtigen Story zugeordnet bleiben. Die
Story-YAML **spiegelt** diese Werte (oder joint sie per ID beim Rendern) — die
Ledger bleiben die schreibende Quelle, die Story-Felder sind die lesbare Sicht.

> Reifegrad: Schätzung + Ist + Kalibrierung sind **implementiert**, aber
> `baseline.json` ist noch leer (`n_items=0`). Bis ~5 abgeschlossene Stories liefert
> die Heuristik `size_est`, aber `dispo_est = null` (erwarteter Zustand). Nach dem
> ersten `retro`-Lauf füllen sich die Schätzwerte.

---

## 5. Status-Lebenszyklen

**Feature** (manuell durch `requirement`/Owner, *plus* automatisches `Active`/`Done`
durch Rollup):

```
Backlog ──► Planned ──► Active ──► Done ──► Archived
                          ▲          │
                          └──────────┘  (re-open, wenn neue Story dazukommt)
```
- `Active` = mindestens eine Story `In Progress`/done, nicht alle done.
- `Done` = **alle** Stories `Done` (vom Board-Tool aus Rollup vorgeschlagen, vom Owner bestätigt).

**Story** (identisch zu heute — `/flow` ist einziger Schreiber):

```
To Do ──► In Progress ──► In Review ──► Done
              │   ▲            │
              ▼   │            ▼
           Blocked ◄───────────┘   (Spec-Lücke, Loop-Schutz N=3, DB-Smoke-FAIL, Rollout-FAIL)
```

Die Story-Übergänge und ihre Auslöser bleiben **1:1** wie in `skills/flow/SKILL.md`
heute — es ändert sich nur das *Backend* (Datei statt `gh project item-edit`).

---

## 6. Speicherformat & Verzeichnislayout

```
<projekt-repo>/
  board/
    board.yaml                 # Board-Meta: schema_version, projekt-slug, id-zähler
    features/
      F-001-provisioning.yaml
      F-002-key-rotation.yaml
    stories/
      S-014-ionos-adapter.yaml
      S-015-cloud-init.yaml
  docs/specs/
    provisioning.md            # AC1…ACn — unverändert die Source of Truth
```

- **Ein YAML pro Feature/Story** (nicht eine große Datei) → minimale git-Merge-Konflikte,
  ein Item = ein Diff, ein Review.
- **YAML statt JSON** für die Items: menschenlesbar, diff-freundlich, kommentierbar.
- **Slug im Dateinamen** (`S-014-ionos-adapter.yaml`) für Auffindbarkeit; die `id`
  im Datei-Body ist die stabile Referenz.
- `board.yaml` hält einen monoton steigenden **ID-Zähler** je Typ (vergibt `F-`/`S-`-Nummern
  kollisionsfrei) und `schema_version` (für spätere Migrationen).
- Das `board: <nummer>`-Feld in `.claude/profile.md` (heute GitHub-Projekt-Nummer)
  entfällt bzw. wird zu `board: file` (Backend-Marker).

---

## 7. Board-Abstraktion (`scripts/board`) — der zentrale Hebel

Statt `gh`-Aufrufe weiter über die Agents zu streuen, kommt **eine** dünne
Schnittstelle. Sie ist der einzige Ort, der das Dateiformat kennt; Agents rufen nur
Verben auf. Das macht den späteren Wechsel des Backends (und das heutige Big-Bang-
Umstellen) zu einer *lokalen* Änderung.

Vorgeschlagene Verben (CLI, später ggf. zusätzlich als Lib für `dev-gui`):

```
board next                      # nächste bereite Story (Queue-Logik, s.u.) → id + spec + AC
board show <id>                 # ein Feature/Story als JSON
board feature add  --title … --goal … --priority …        → F-###
board story   add  --parent F-### --title … --spec … --implements AC1,AC2
board set <id> status <wert> [--reason …]                  # NUR /flow für Story-Status
board set <id> <feld> <wert>
board list  [--type feature|story] [--status …] [--parent F-###]
board rollup <F-###>            # progress neu berechnen
board lint                      # Integrität: parent existiert, depends auflösbar, AC in Spec, ids eindeutig
board ready [--quiet]           # Readiness-Gate: prüft alle To-Do-Stories auf Abarbeitbarkeit (F-008)
board export-github             # einmaliger Import: GitHub-Board → board/ (Migration)
```

**Queue-Logik von `board next`** (ersetzt `gh project item-list` in `flow/SKILL.md:22`):
die erste Story mit `status=To Do`, deren `depends` alle `Done` sind, nach
`priority` (P0 zuerst), Tie-Break Feature-`priority`, dann `id`.

**Single-Writer bleibt:** Nur `/flow` ruft `board set <story> status …`. `requirement`
darf `feature add`/`story add` und nicht-Status-Felder setzen. Das ist die heutige
Regel „`/flow` ist einziger Schreiber von Board-Status", nur auf die CLI gehoben.

---

## 8. Auswirkung auf die bestehenden Agents/Skills

| Komponente | Heute | Nach Umstellung |
|---|---|---|
| `new-project` | `gh project create`, Nummer ins Profil | `board/`-Skelett + `board.yaml` anlegen; `board: file` ins Profil |
| `requirement` | `gh issue create` + `gh project item-add`, `Spec:`/`implements:` in Body | `board feature add` + `board story add` (legt **Feature** an, hängt Stories an); Spec unverändert unter `docs/specs/` |
| `flow` | `gh project item-list` lesen, `gh project item-edit` schreiben | `board next` lesen, `board set … status …` schreiben — **Logik identisch**; schreibt Metrik-Ledger mit dem numerischen Anteil der Story-ID als `int`-`item`-Schlüssel (§4.4, `S-014` → `14`) |
| `estimator` (**neu**) | — (Schätzung steckt deterministisch in `/flow`) | optionaler Schätz-Agent: liefert bei L/XL `dispo_est` + `estimate_note` (Hybrid, §4.4); S/M bleiben token-frei |
| `coder/reviewer/tester` | lesen Item-Body + Spec | lesen `board show <story>` + Spec — schreiben weiterhin **keinen** Status |
| `cicd` | git merge/push, kein Board-Status | unverändert; setzt ggf. `pr`/`branch` via `flow` |
| `adopt` | `gh project create` + Backlog als Issues | `board/`-Skelett + Funde als Stories (ein Auto-Feature „Adoption-Backlog") |
| `dev-gui` | — | neuer Read-Only-Aggregator + Board-View (siehe §9) |
| metrics (`items.jsonl`) | parallel zum Board | unverändert — `size_est`/`ep_est`/`ep_act` bleiben in `.claude/metrics/` |

Wichtig: **AC bleiben in `docs/specs/`** (Drift-Gate, Spec-Status `draft|active|superseded`
unverändert). Wir verschieben *nicht* die Akzeptanzkriterien ins Board — nur die
Queue/Status/Hierarchie.

---

## 9. dev-gui — die zentrale, projektübergreifende Übersicht

`dev-gui` (React + Express, bereits vorhanden) bekommt einen **Board-Aggregator**:

1. **Scan:** konfigurierte Repo-Wurzeln (z.B. `~/Git/Studis-Softwareschmiede/*`)
   nach `board/`-Ordnern durchsuchen, Features/Stories einlesen.
2. **Index (Cache):** im Speicher/leichtgewichtig halten — **kein** persistenter
   Zweit-Store, die Dateien bleiben Source of Truth. Re-Scan bei Dateiänderung
   (Watcher) oder on-demand.
3. **View:** dreistufige Übersicht **Projekt → Feature → Story** mit Status-Spalten,
   Rollup-Balken je Feature, Filtern (Projekt, Status, Label).
4. **Schreiben (optional, Phase 2):** Änderungen aus der GUI gehen **durch die
   `board`-CLI/Lib in die Dateien** zurück (gleicher Single-Writer-Pfad, danach
   git-commit) — nie direkt in einen DB-Cache.

So entsteht die gewünschte *eine* Übersicht über alles, ohne die „Files = SoT"-Regel
zu brechen.

---

## 10. Migration — direkter Schnitt (Big Bang)

Trotz Big Bang sichern wir den Cut so ab, dass ein Rückfall jederzeit möglich ist
(git!). Ablauf je Repo, an einem Stichtag:

```
[0] Voraussetzung: scripts/board + Agents/Skills auf File-Backend umgestellt (ein PR, getestet).
[1] Export:   board export-github  →  liest aktuelles GitHub Project v2 (Issues, Status,
              Priority, depends, Spec-Refs) und schreibt board/features/ + board/stories/.
              Heuristik Feature-Bildung: ein Auto-Feature je Spec-Datei / Label-Cluster;
              Owner reviewt + benennt Features nach.
[2] Lint:     board lint  →  parent/depends/AC-Integrität grün.
[3] Review:   ein git-PR „Board → Files" — vollständig im Diff sichtbar, Owner prüft.
[4] Cut:      PR mergen. profile.md: board → file. GitHub Project wird read-only
              archiviert (NICHT gelöscht) als Rückfallebene.
[5] dev-gui:  Aggregator aktivieren → zentrale Übersicht live.
```

**Rückfallebene** (statt Parallelbetrieb): Da der Export *ein git-Commit* ist und das
GitHub-Board nur archiviert (nicht gelöscht) wird, ist Rollback = `git revert` des
Cut-PR + Profil zurück auf die Board-Nummer. Kein laufender Sync nötig.

**Reihenfolge der Repos:** zuerst `dev-gui` selbst (Dogfooding — die GUI verwaltet ihr
eigenes Board), dann ein kleines Projekt, dann der Rest.

---

## 11. Risiken & offene Punkte

| Risiko / Frage | Abmilderung / Entscheidung nötig |
|---|---|
| **ID-Vergabe bei parallelen Branches** (zwei Branches vergeben S-020) | Zähler in `board.yaml`; `board lint` erkennt Doppel-IDs; bei Merge-Konflikt manuell. Alternativ ULID/kurz-Hash statt laufender Nummer. |
| **git-Merge-Konflikte auf Item-Dateien** | Ein Datei pro Item + append-arme Felder minimieren; `updated_at`-Konflikte sind trivial lösbar. |
| **Feature-Bildung beim Export** ist heuristisch | Owner-Review im Cut-PR; lieber grob ein Auto-Feature je Spec, danach nachschärfen. |
| **Verlust GitHub-Komfort** (Web-UI, Mobile, Benachrichtigungen) | `dev-gui`-View ersetzt Web-UI; Issues/PR-Diskussionen können optional in GitHub bleiben (Code-Review ≠ Board). |
| **Status-Konsistenz Feature↔Story** | `board rollup` ist die *einzige* Quelle für Feature-`progress`/`Active`/`Done`; nie von Hand. |
| **dev-gui Multi-Repo-Pfad-Konfiguration** | Repo-Wurzeln + Auth (read-only FS) in dev-gui-Config; für entfernte Repos später git-Pull/Read-API. |
| **Soll `requirement` Features automatisch bilden oder fragt es?** | Vorschlag: bei vager Anforderung 1 Feature + n Stories vorschlagen, per `AskUserQuestion` bestätigen. |

---

## 12. Nächste Schritte (wenn Konzept ok)

1. **Schema festnageln:** Feld-Liste aus §4 als YAML-Schema (`board/board.schema.*`) + `board lint`-Regeln.
2. **`scripts/board` spezifizieren** (Verben §7) — als eigene Spec unter `docs/specs/board-cli.md`.
3. **Agents/Skills-Diff** (§8) je Komponente als Story-Backlog für `/flow` (Dogfooding auf `dev-gui`).
4. **Dispo ans Board hängen** (§4.4): `dispo_est`/`dispo_act`/`estimate_note` als Story-Felder; `/flow` schreibt den numerischen Anteil der Story-ID als `int`-`item`-Schlüssel in die Ledger (ID-Brücke, `S-014` → `14`); optionaler `estimator`-Agent als eigene Spec (`docs/specs/estimator.md`).
5. **dev-gui-Aggregator** (§9) als eigenes Feature im dev-gui-Board.
6. **Export-Tool + Cut-Runbook** (§10) als letzte Story vor dem Stichtag.

> Bewusst NICHT in v1: persistente zentrale DB, GUI-Schreibpfad (Phase 2),
> Sprints/Iterationen, externe Repos über Netzwerk. Erst Files + Übersicht stabil,
> dann erweitern.
