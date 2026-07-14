---
id: id-block-reservation
title: ID-Nummernblock-Reservierung bei parallelen Feature-Batches
status: active
area: flow-orchestrierung
version: 1
spec_format: use-case-2.0
---

# Spec: ID-Nummernblock-Reservierung bei parallelen Feature-Batches  (`id-block-reservation`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Verhindert kollidierende Neu-IDs, wenn mehrere Feature-Batches **parallel** laufen. Heute vergibt jeder Batch dezentral „die nächste freie Nummer im eigenen Branch-Stand" für nummerierte Doku-Artefakte (Business Rules `BR-###`, Architektur-Entscheidungen `ADR-###`, Konzept-Komponenten `C-###`). Weil parallele Batches von je einem eigenen `origin/<default_branch>`-Stand abzweigen, „sehen" sie die frisch vergebenen IDs der anderen Batches nicht — mehrere Batches greifen auf denselben freien Wert zu. **Realer Vorfall (2026-07-13, ki-investment):** drei parallele Batches (S-018 auf main, F-011, F-012) vergaben dieselbe Regel-ID `BR-132` (dreifach) plus kollidierende `BR-133`; die Konsolidierung erzwang manuelles Umnummerieren (`BR-134`, `BR-135`) und grep-getriebenes Nachziehen aller Referenzen. Diese Spec macht die ID-Vergabe **koordiniert**: der Feature-Drain reserviert beim Batch-Start je ID-Namespace einen zusammenhängenden Nummernblock in einem **zentralen Reservierungs-Ledger auf dem `default_branch`**; `coder`/`dba` vergeben neue IDs ausschließlich **innerhalb** des dem Feature reservierten Blocks. Zwei parallele Batches können so keine kollidierenden Neu-IDs mehr erzeugen — die Konsolidierung merge't ohne Umnummerierung.

## Main Success Scenario
1. `scripts/board-feature-drain.sh <F-###>` startet einen Feature-Batch und ermittelt zu Drain-Start (Phase `dossier`, **vor** der ersten Story-Session) die ID-Namespaces, die das Feature voraussichtlich berührt (mindestens `BR`, `ADR`, `C` — konservativ: alle drei, sofern nicht explizit ausgeschlossen).
2. Für jeden dieser Namespaces reserviert der Drain **atomar** gegen den `default_branch` einen zusammenhängenden Block (Default-Größe konfigurierbar, Default 10) und schreibt einen Eintrag ins zentrale Reservierungs-Ledger `board/id-reservations.yaml`, das auf `origin/<default_branch>` committet + gepusht wird.
3. Der reservierte Block wird dem Feature sichtbar hinterlegt: authoritativ im Ledger auf `main` **und** menschenlesbar in `board/runs/<F-###>/dossier.md` (ephemer, injiziert in die Story-Sessions).
4. `coder`/`dba` vergeben in den Story-Sessions neue `BR-###`/`ADR-###`/`C-###`-IDs **ausschließlich** aus dem für dieses Feature reservierten Block des jeweiligen Namespaces.
5. Nach dem finalen Feature→`default_branch`-Merge (bzw. Batch-Ende) markiert der Drain im Ledger den tatsächlich verbrauchten High-Water-Mark; der ungenutzte Rest wird als `released` freigegeben und darf von späteren Reservierungen wiederverwendet werden.

## Alternative Flows
### A1: Parallele Reservierung (Push-Konflikt)
- Reserviert ein zweiter Batch gleichzeitig, scheitert der `git push` des Ledger-Eintrags (der andere Batch hat zuerst committet). Der Drain **re-fetcht** `origin/<default_branch>`, berechnet den **nächsten** freien Block hinter allen bereits eingetragenen Reservierungen neu und wiederholt Commit+Push (optimistische Nebenläufigkeit, begrenzte Retries). Ein bereits von einem anderen Batch reservierter Bereich wird **nie** erneut vergeben.

### A2: Board-weiter `/flow`-Einzellauf (kein `--parent`)
- Ein board-weiter `/flow`-Lauf, der eine Story direkt auf `default_branch` landet und dabei einen neuen `BR-###`/`ADR-###`/`C-###` einführt, reserviert **ebenfalls** über denselben Ledger-Mechanismus (analog zum Vorfall „S-018 auf main"), damit ein Einzellauf und ein parallel laufender Feature-Batch nicht kollidieren. Ohne neue namespaced ID: keine Reservierung nötig (Verhalten unverändert).

### E1: Block erschöpft
- Braucht ein Feature mehr IDs als sein reservierter Block fasst, reserviert der Drain (oder `/flow` bei Bedarf) über **denselben** atomaren Mechanismus einen **weiteren** zusammenhängenden Block für denselben Namespace/Feature. Es gibt **kein** stilles Überlaufen in einen fremden oder unreservierten Bereich.

### E2: Ledger-Schreib-/Push-Fehler
- Scheitert der Ledger-Commit/Push endgültig (nach Retries), bricht der Drain **vor** der ersten Story-Session mit klarer Diagnose ab (keine Story startet ohne gültige Reservierung) — statt blind mit dezentraler Vergabe fortzufahren und die Kollision zu riskieren. Der Abbruch wird in `board/runs/<F-###>/state.yaml` (`last_error`) vermerkt.

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

- **AC1** — Reservierung bei Batch-Start: `board-feature-drain.sh <F-###>` reserviert zu Drain-Start (vor der ersten Story-Session) für jeden berührten ID-Namespace (`BR`, `ADR`, `C`) genau einen zusammenhängenden Block der konfigurierbaren Default-Größe (Default 10) und trägt ihn ins Reservierungs-Ledger `board/id-reservations.yaml` ein.
- **AC2** — Atomarität gegen `default_branch`: der Ledger-Eintrag wird nach `origin/<default_branch>` committet + gepusht, **bevor** irgendeine Story-Session dieses Batches startet. Scheitert der Push wegen eines konkurrierenden Batches, re-fetcht der Drain, berechnet den nächsten freien Block neu und wiederholt (begrenzte Retries) — ein bereits eingetragener Bereich wird nie erneut vergeben. *(deckt A1)*
- **AC3** — Disjunkte Blöcke bei Nebenläufigkeit: reservieren zwei Batches denselben Namespace quasi-gleichzeitig, erhalten sie **nicht-überlappende** Nummernbereiche (Concurrency-/Property-Szenario: keine zwei aktiven `active`-Reservierungen desselben Namespace teilen einen Wert).
- **AC4** — Vergabe innerhalb des Blocks (HART): `coder`/`dba` vergeben neue `BR-###`/`ADR-###`/`C-###` **ausschließlich** aus dem dem Feature reservierten Block des jeweiligen Namespaces. Eine Neu-ID außerhalb des reservierten Blocks (bei aktivem Batch, der diesen Namespace berührt) ist ein **harter Reviewer-Befund** (`reviewer/id-out-of-block`, Critical) → `CHANGES-REQUIRED`. Der reservierte Block ist für die Story-Sessions aus Ledger **und** Dossier lesbar.
- **AC5** — Block-Nachreservierung bei Erschöpfung: reicht der Block nicht, reserviert der Drain über denselben atomaren Mechanismus (AC2) einen weiteren Block für denselben Namespace/Feature; kein stiller Überlauf in fremde/unreservierte Bereiche. *(deckt E1)*
- **AC6** — Kollisionsfreie Konsolidierung (Kern-Akzeptanz): der Merge zweier parallel gelaufener Feature-Batches nach `default_branch` erzeugt **keine** kollidierenden Neu-IDs und erfordert **kein** Umnummerieren — der Vorfall 2026-07-13 (`BR-132` dreifach) kann sich unter diesem Mechanismus nicht wiederholen.
- **AC7** — Idempotenz: ein erneuter Drain-Start desselben Features erkennt dessen bestehende, noch `active` Reservierung und **legt keinen zweiten Block an** (keine Doppel-Allokation, kein Ledger-Wachstum ohne Anlass).
- **AC8** — Ledger-Schema & -Persistenz: `board/id-reservations.yaml` folgt dem definierten Schema (siehe Verträge), liegt auf dem `default_branch` und ist **committet** (NICHT gitignored wie `board/runs/`) — es ist die cross-Batch-sichtbare Single Source of Truth der Reservierungen.
- **AC9** — Board-weite `/flow`-Parität: ein board-weiter `/flow`-Lauf (ohne `--parent`), der eine neue namespaced ID einführt, reserviert über denselben Ledger-Mechanismus, bevor er die ID vergibt; führt der Lauf keine neue namespaced ID ein, bleibt sein Verhalten unverändert (keine Reservierung, kein Ledger-Diff). *(deckt A2)*
- **AC10** — Freigabe/High-Water-Mark: nach erfolgreichem finalen Merge (bzw. Batch-Ende) vermerkt der Drain den verbrauchten High-Water-Mark im Ledger und gibt den ungenutzten Rest als `released` frei; freigegebene Bereiche dürfen von späteren Reservierungen wiederverwendet werden.
- **AC11** — Harter Abbruch statt Blind-Vergabe: kann keine gültige Reservierung angelegt werden (Ledger-Push endgültig fehlgeschlagen), startet **keine** Story-Session; der Drain bricht mit Klartext-Diagnose ab und setzt `last_error` in `state.yaml`. *(deckt E2)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace id-block-reservation#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.
> Da agent-flow `language: md` ist (No-Op-Build), erfolgt die Abnahme der Doku-/Agent-Def-Anteile
> als Doku-Inspektion; die deterministische Ledger-/Reservierungs-Mechanik (`board-feature-drain.sh`)
> wird über ein mechanisches Smoke-Skript belegt (analog `tests/board-cli`, Nebenläufigkeits-Szenario zu AC3).

## Verträge

### Reservierungs-Ledger `board/id-reservations.yaml` (committet, cross-Batch-Single-Source-of-Truth)
Feldnamen/Enums sind verbindlich — Änderungen nur über Spec-Fortschreibung. `board/id-reservations.yaml` ist **committet** auf dem `default_branch` (im Gegensatz zum gitignored `board/runs/`).

```yaml
schema_version: 1
namespaces:
  BR:
    block_size: 10          # Default-Blockgröße für diesen Namespace
    reservations:
      - feature_id: F-011    # F-### oder S-### (board-weiter /flow-Einzellauf)
        range_start: 140     # inklusive
        range_end: 149       # inklusive
        status: active       # enum: active | released
        reserved_at: '2026-07-13T09:00:00Z'   # ISO-8601
        high_water: 143      # höchste tatsächlich vergebene Nummer (oder null)
  ADR: { block_size: 10, reservations: [] }
  C:   { block_size: 10, reservations: [] }
```

- **Reserve-Operation (atomar):** `origin/<default_branch>` fetchen → nächsten freien Block hinter allen `active`+`released`-Belegungen berechnen → Eintrag anhängen → committen → pushen. Push-Reject → re-fetch + neu berechnen + retry (begrenzt). Kein Wert wird von zwei `active`-Reservierungen desselben Namespace geteilt (AC3).
- **Konsument-Vertrag:** `coder`/`dba` lesen den für das laufende Feature reservierten Block (Ledger oder injiziertes Dossier) und vergeben strikt daraus (AC4).
- **Reviewer-Gate-Erweiterung:** `reviewer/id-out-of-block` (Critical) — neue namespaced ID außerhalb des reservierten Blocks bei aktivem Batch → `CHANGES-REQUIRED` (AC4).
- **Drain-Erweiterung:** `board-feature-drain.sh` reserviert in Phase `dossier` (vor der ersten Story-Session) und aktualisiert High-Water/`released` am Batch-Ende (AC1/AC10); Reservierungsfehler → Abbruch vor Story-Start + `state.yaml.last_error` (AC11).

## Edge-Cases & Fehlerverhalten
- **Namespace vom Feature nicht berührt:** wird kein `BR`/`ADR`/`C` neu vergeben, bleibt der reservierte Block ungenutzt und wird am Ende vollständig `released` (kein Verbrauch, keine Lücke — nur ein temporär belegter Bereich).
- **Abgebrochener Batch (kein Merge):** die `active`-Reservierung bleibt im Ledger stehen (belegt den Bereich weiter) — ein erneuter Drain-Start desselben Features reuse't sie (AC7); ein anderer Batch weicht ihr aus. Manuelle Freigabe abgebrochener Reservierungen ist Owner-/Reconcile-Scope, nicht Teil dieser Spec.
- **Bestehende, historisch vergebene IDs unterhalb des ersten Blocks:** die Block-Berechnung startet hinter dem höchsten bereits **im Bestand** vergebenen Wert je Namespace (kein Re-Use bestehender IDs).
- **Ledger fehlt (Erstlauf):** wird beim ersten Reserve-Vorgang aus dem Schema angelegt (leere `reservations`-Listen), committet + gepusht.

## NFRs
- Deterministische Block-Berechnung (kein Zufall) — reproduzierbar aus dem Ledger-Stand.
- Atomare, konflikt-tolerante Reservierung (optimistische Nebenläufigkeit) statt globaler Lock — parallele Batches blockieren sich nicht dauerhaft, sondern retryen kurz.
- Token-arm: reine deterministische Bash/Python-Mechanik im Drain, kein zusätzlicher LLM-Call für die Reservierung.

## Nicht-Ziele
- **Kein** globaler Sperr-/Locking-Dienst und **keine** zentrale ID-Datenbank — die Koordination läuft ausschließlich über das committete Ledger + optimistische Nebenläufigkeit.
- **Keine** Rückwirkung auf bereits vergebene IDs (kein Umnummerieren des Bestands).
- **Keine** Freigabe/Garbage-Collection abgebrochener Reservierungen (Owner-/Reconcile-Scope).
- **Keine** neue Board-CLI-Story-/Feature-ID-Vergabe-Änderung (`next_story_id`/`next_feature_id` sind bereits zentral im Board serialisiert und nicht betroffen).

## Abhängigkeiten
- `[[feature-batch-orchestration]]` — der Reserve-Schritt reiht sich in die Phase `dossier` des Feature-Drains ein; die High-Water/`released`-Aktualisierung an das finale Merge-Ende (AC6/AC10). `board/runs/<F-###>/dossier.md` transportiert den Block in die Story-Sessions.
- Agent-Defs `agents/coder.md`, `agents/dba.md` (Vergabe innerhalb des Blocks, AC4), `agents/reviewer.md` (Gate `reviewer/id-out-of-block`, AC4).
- ID-Namespaces `BR-###` / `ADR-###` / `C-###` aus `docs/data-model.md` / `docs/architecture.md` / `docs/concept.md` (Bestands-High-Water je Namespace als Startpunkt der Block-Berechnung).
- Entscheidungsquelle: Owner-Auftrag 2026-07-13 (Vorfall `BR-132` dreifach, ki-investment).
