---
id: build-version-verification
title: cicd-Versionsstempel + Rollout-Abgleich datei-/label-basiert — Rationale in knowledge/cicd.md
status: active
version: 1
spec_format: use-case-2.0
area: auslieferung
---

# Spec: cicd-Versionsstempel + Rollout-Abgleich (datei-/label-basiert)  (`build-version-verification`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (ändert `agents/cicd.md` + `knowledge/cicd.md`), `reviewer` (Drift-Gate + Schreib-Hoheit), `tester` (prüft die AC).
>
> **Subsystem-Bindung.** Diese Spec ist die cicd-Seite des Fabrik-Standards „robuste Build-Versionierung" — Schwester der Scaffold-Seite [[build-version-stamping]]. Sie richtet den cicd-`version-stamp`-Modus + den Rollout-Versions-Abgleich auf die **datei-/label-basierte** Quelle aus (weg von der recreate-überschreibbaren ENV) und kodiert die Rationale als datierten Befund + stabile Regel-IDs in `knowledge/cicd.md`.

## Zweck

Der cicd-Agent stempelt und verifiziert die Build-Version aus der **einen** Quelle (`APP_VERSION` + git-SHA) **datei-/label-basiert**, nicht ENV-first — weil Container-Recreate-Werkzeuge die Alt-Container-ENV 1:1 übernehmen und so die Versionsanzeige einfrieren. Die Rationale + der datierte Befund + die Regel-IDs landen im cicd-Knowledge, damit `reviewer` und `tester` die Regel künftig aktiv schützen (Drift-Gate + Test-Approach).

## Kontext / Designnuancen (bindend)

- **Vorfall flashrescue 2026-07-19:** Container-Recreate-Werkzeuge (z.B. dev-guis „Update") übernehmen beim Neuaufbau die ENV des Alt-Containers **1:1** — inkl. der alten `APP_VERSION` — und überschreiben damit die des neuen Images. Ergebnis: neuer Code, eingefrorene Versionsanzeige, wiederholt Fehlalarm.
- **Datei schlägt ENV.** Die gebrannte Image-Datei ist recreate-immun; die ENV nicht. Die cicd-Read-/Verify-Reihenfolge spiegelt deshalb die App-Kette **Datei/Label → ENV → dev**.
- **App kann eigene OCI-Labels nicht von innen lesen** — Labels sind Registry-/`docker inspect`-Metadaten für Tools, nicht die App-Selbstauskunft. Der cicd-Abgleich nutzt das Label (von außen via `docker inspect`) gegen die App-`/version` (datei-basiert, von innen) — beide Quellen sind unabhängig, deshalb ist ihr Abgleich aussagekräftig.
- **Schreib-Hoheit knowledge/cicd.md:** die neue F-/P-Regel + der Befund gehen in das bestehende cicd-Pack (Fallen/Patterns/Reviewer-Checklist/Test-Approach); F02 wird um den Recreate-Overwrite-Fall **amendiert**, nicht ersetzt.

## Main Success Scenario

1. `cicd version-stamp` bereitet `Dockerfile`/`build.yml` eines Projekts so vor, dass die Version zur Build-Zeit in eine **Image-Datei** gebrannt wird und die OCI-Labels aus der EINEN Quelle stammen.
2. Beim `ship`/`rollout` liest cicd die laufende Version **datei-/label-first** (`org.opencontainers.image.version` bzw. `/version`), ENV nur als letzter Fallback.
3. Nach dem Container-Recreate gleicht cicd `/version` (datei-basiert) gegen das OCI-Image-Label ab; bei Mismatch → sichtbare WARN.
4. `knowledge/cicd.md` trägt den datierten Befund + die Regel-IDs, sodass `reviewer`/`tester` das Muster künftig erzwingen.

## Alternative Flows

### A1: Versions-Endpunkt fehlt
- Fehlt `/version` im Ziel-Projekt, meldet cicd wie bisher eine Spec-Lücke (Board-Item, [[build-version-stamping]] AC8) — kein Rollout-Blocker (`cicd/P01`).

### E1: Version-Abgleich Mismatch
- `/version` ≠ OCI-Label nach Rollout → **sichtbare WARN** im Rollout-Gate-Output (kein Hard-Fail, da Diagnose-Signal), mit Hinweis auf mögliche ENV-Overwrite-Regression.

## Acceptance-Kriterien

- **AC1** — `agents/cicd.md` `version-stamp`-Modus (Abschnitt D) brennt die Version zur Build-Zeit in eine **Image-Datei** (nicht ENV-only) UND setzt die OCI-Labels `org.opencontainers.image.version`/`.revision`/`.created` aus der **einen** Quelle (`APP_VERSION` + git-SHA); die bisherige ENV-only-Vorgabe wird als recreate-unsicher abgelöst (→ [[build-version-stamping]] AC2/AC4).
- **AC2** — Der cicd-Rollout-Versions-**Read** (Abschnitt A3) liest die laufende Version **Datei-/Label-first** (`org.opencontainers.image.version` via `docker inspect` bzw. `/version`), ENV nur als **letzter** Fallback; die Reihenfolge spiegelt die App-Kette Datei → ENV → dev.
- **AC3** — Der cicd-Rollout-**Versions-Abgleich** nach dem Recreate vergleicht `/version` (datei-basiert) gegen das OCI-Image-Label `org.opencontainers.image.version`; Mismatch → **sichtbare WARN** — als Erweiterung des bestehenden A3-Versions-Endpunkt-Abgleichs (**anschließen, nicht duplizieren**). *(deckt E1)*
- **AC4** — `knowledge/cicd.md` trägt einen **datierten Befund** „flashrescue 2026-07-19": Container-Recreate-Werkzeuge übernehmen die Alt-Container-ENV 1:1 (inkl. alter `APP_VERSION`) und überschreiben die des neuen Images → eingefrorene Versionsanzeige; die datei-basierte Quelle ist immun.
- **AC5** — `knowledge/cicd.md` kodiert die Regel als stabile Rule-IDs: eine **F-Regel** (ENV als Versionsquelle ist recreate-überschreibbar — Anti-Pattern) **und** eine **P-Regel** (datei-gebrannte Version als Selbstauskunfts-Quelle + OCI-Labels ergänzend + Frontend-no-cache); die bestehende `cicd/F02` wird um den Recreate-Overwrite-Fall **amendiert** (nicht ersetzt).
- **AC6** — `knowledge/cicd.md` dokumentiert explizit: eine App kann ihre **eigenen OCI-Labels von innen nicht lesen** (nur Registry/`docker inspect`) — Labels sind ergänzendes Image-Metadatum für Tools/Registry, **nicht** die `/version`-Quelle.
- **AC7** — Die neuen Regeln landen in **Reviewer-Checklist** (Dockerfile: Version aus **Datei** nicht ENV; OCI-Labels vorhanden; ENV-only-Versionsquelle → Important) **und** **Test-Approach** (Version-Abgleich Datei/Label nach Rollout) von `knowledge/cicd.md`.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace build-version-verification#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.
> Hinweis: `language: md` — Doku-Diffs → `tester` prüft die AC gegen Agent-/Pack-Text (kein Laufzeit-Smoke).

## Verträge

### Geänderte Artefakte
```
agents/cicd.md      # Abschnitt D (version-stamp): Datei-Brennen + OCI-Labels aus EINER Quelle
                    # Abschnitt A3: Version-Read Datei-/Label-first; Version-Abgleich /version vs. OCI-Label
knowledge/cicd.md   # F02-Amendment + neue F-Regel + neue P-Regel; datierter Befund flashrescue 2026-07-19;
                    # Reviewer-Checklist- + Test-Approach-Zeilen
```

### cicd-Version-Read-Reihenfolge (A3, kanonisch)
```
1. docker inspect → org.opencontainers.image.version   (Label, von außen)
2. curl /version → { version } aus gebrannter Datei     (App-Selbstauskunft, von innen)
3. ENV APP_VERSION                                       (letzter Fallback)
4. "unknown"/"dev"
```

### Version-Abgleich (A3, Erweiterung — nicht neu)
```
RUNNING = /version (datei-basiert)  ;  IMAGE = org.opencontainers.image.version (Label)
RUNNING == IMAGE  → OK   |   RUNNING != IMAGE → WARN (mögliche ENV-Overwrite-Regression)
```

## Edge-Cases & Fehlerverhalten

- **`/version` fehlt** → Spec-Lücke melden (A1, `cicd/P01`), Label-Read genügt für die Rollout-Version — kein Blocker.
- **Label fehlt (Alt-Image ohne OCI-Labels)** → Fallback auf `/version`, sonst ENV, sonst `unknown` — fail-soft.
- **Mismatch /version vs. Label** → WARN, kein Hard-Fail (Diagnose-Signal für ENV-Overwrite-Regression).

## NFRs

- **Fail-soft:** Version-Read/-Abgleich brechen den Rollout nie ab (WARN statt FAIL bei Mismatch/Fehlen).
- **Drift-Schutz:** die neuen Rule-IDs machen die Regel für den `reviewer` erzwingbar (Datei-Quelle > ENV; OCI-Labels vorhanden).

## Nicht-Ziele

- Die Scaffold-Template-Änderungen (Dockerfiles, build.yml, Endpunkt-Vorlage) — Schwester-Spec [[build-version-stamping]].
- Änderung der `ship`-Kern-Sequenz (merge → push → CI-Watch → Rollout → Prune) — nur der Version-Read/-Abgleich innerhalb A3 wird geschärft.
- Globale Knowledge-Destillation (projekt-lokal → global) — macht `retro` via PR+Gate.

## Abhängigkeiten

- [[build-version-stamping]] — definiert Datei-Pfad + OCI-Label-Keys, die cicd hier liest/verifiziert (Bereich `vorlagen-scaffolding`).
- `agents/cicd.md` — `version-stamp`-Modus (Abschnitt D) + Rollout-Version-Read/-Abgleich (A3).
- `knowledge/cicd.md` — bestehendes cicd-Pack (F02-Amendment + neue Regel-IDs).
