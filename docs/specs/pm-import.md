---
id: pm-import
title: PM-Import — pm-skills-Artefakte als strukturierte Requirement-Quelle (Erweiterung obsidian-ingest)
status: draft
area: anforderung-intake
version: 1
spec_format: use-case-2.0
---

# Spec: PM-Import  (`pm-import`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Basis-Spec:** `[[obsidian-ingest]]` — dieser Entwurf ist **keine neue Pipeline**, sondern erweitert Stufe a/b von `/agent-flow:from-notes` um einen deterministischen Erkennungs- und Mapping-Pfad für pm-skills-Artefakte. Reader, Fragenkatalog-Gate, ID-Kette (`IDEA→C→Spec`), Frontmatter-Stempel und `--audit` gelten unverändert.
> **Konzept-Herkunft:** bewusst noch **ohne** `(← C-NNN)` — Entwurf aus Chat-Session 18.07.2026 (Obsidian-Quelle: `300 Projekte/Last30Days und PM/Mapping Schema PM zu Agent Flow.md`). Der `--audit` wird diese Spec bis zum Nachziehen des Konzept-Ankers korrekt als «Waise aufwärts» melden — das ist beabsichtigt und Input für `[[reconcile]]` Stufe 3.

## Zweck
Notizen aus dem pm-skills-Plugin (PRD, Problem-Statement, Hypothesen, User Stories, Acceptance-Criteria, Edge-Cases, ADR, Launch-Checklist) sind **strukturierter** als freie Ideennotizen. Der PM-Import erkennt solche Artefakte im Notiz-Korpus und übersetzt sie **feldgenau** in die Fabrik-Artefakte, statt sie wie Freitext neu zu interpretieren — weniger Fragenkatalog, weniger Interpretationsverlust, gleiche Verträge.

## Main Success Scenario
1. Der Mensch legt pm-skills-Artefakte als `.md`-Notizen im verknüpften Obsidian-Projektordner ab.
2. `/agent-flow:from-notes` läuft wie in `[[obsidian-ingest]]` spezifiziert; der Reader liefert den Korpus.
3. Die **Artefakt-Klassifikation** markiert erkannte pm-skills-Notizen mit ihrem Artefakt-Typ; unklassifizierte Notizen laufen unverändert den bestehenden Ideen-Pfad.
4. Stufe a/b wenden für klassifizierte Notizen die **Mapping-Tabelle** (siehe Verträge) an; nicht abbildbare Abschnitte gehen in `docs/concept.md` + Fragenkatalog.
5. Stufe c bleibt unverändert (`requirement` zerlegt in Board-Items auf Spec + AC-Nummern).

## Alternative Flows
### A1: Gemischter Ordner (PM-Artefakte + freie Ideennotizen)
- Beide Pfade laufen im selben Lauf; die ID-Kette behandelt beide gleich (`IDEA-NNN` je Notiz).

### E1: Notiz sieht aus wie ein PM-Artefakt, ist aber unvollständig/mehrdeutig
- Kein stiller Fallback auf den Ideen-Pfad: Die Unklarheit («als `<typ>` erkannt, Sektion X fehlt/widersprüchlich») wird als Fragenkatalog-Eintrag vorgelegt (Schwelle wie `obsidian-ingest` AC10).

## Acceptance-Kriterien
- **AC1** — **Erkennung, additiv:** Die Pipeline klassifiziert Notizen des Korpus als pm-skills-Artefakt-Typ (`prd | problem-statement | hypothesis | user-stories | acceptance-criteria | edge-cases | adr | launch-checklist`) anhand Frontmatter (falls vorhanden) oder Struktur-Heuristik (charakteristische Sektionen, Given/When/Then-Blöcke). Unklassifizierte Notizen durchlaufen **unverändert** den bestehenden Ideen-Pfad — kein Verhalten bestehender Läufe ändert sich.
- **AC2** — **Deterministisches Mapping:** Für klassifizierte Notizen wenden Stufe a/b die Mapping-Tabelle (Verträge) an. Gleicher Input ⇒ gleiche Zuordnung; keine freie Neu-Interpretation von Inhalten, die ein definiertes Ziel haben.
- **AC3** — **Hypothesen → BR-Kandidaten:** Jedes `hypothesis`-Artefakt erzeugt einen `BR-NNN`-Entwurf in `docs/architecture.md` (Verhalten) bzw. `docs/data-model.md` (Validierung) mit Markierung «Kandidat» und mitgeführtem Messkriterium; die Ziel-Spec referenziert nur `(→ BR-NNN)`. Die Nummer ist die **nächste freie** `BR-NNN` über beide Dateien hinweg (nie wiederverwendet).
- **AC4** — **GWT → AC:** `acceptance-criteria`-Artefakte (Given/When/Then) werden zu nummerierten, testbaren Acceptance-Kriterien der Ziel-Spec. AC-IDs sind stabil (Re-Ingest hängt an, nummeriert nie um); die `@trace`-Konvention (`@trace <feature-slug>#AC<n>[,BR-NNN]`) gilt unverändert.
- **AC5** — **Kein stiller Verlust:** Abschnitte ohne definiertes Mapping-Ziel (z.B. PRD-Risiken) landen in `docs/concept.md` **und** als Fragenkatalog-Eintrag mit Quellnotiz-Bezug — nie stilles Weglassen, nie Einfügen fremder Sektionen in die Spec-Vorlage.
- **AC6** — **Idempotenz:** Re-Ingest einer bereits übernommenen PM-Notiz (erkannt über `idea_id`/`sync_hash` gemäss `obsidian-ingest` AC15/AC17) aktualisiert die bestehenden Ziel-Artefakte statt Duplikate anzulegen.
- **AC7** — **ID-Kette unverändert:** PM-Artefakte erhalten `IDEA-NNN` und Frontmatter-Stempel exakt nach `obsidian-ingest` AC15–AC17; die Kette `IDEA → C → Spec → BR → Story → @trace` bleibt für PM-Quellen durchgängig, und `--audit` (AC19–AC22) deckt sie ohne Sonderfall ab.
- **AC8** — **Launch-Checklist → Stufe c:** Punkte einer `launch-checklist` fliessen als Zerlege-Hinweise an den `requirement`-Agenten in Stufe c; Board-Items zeigen weiterhin ausschliesslich auf Spec + AC-Nummern (kein zweiter Item-Pfad, kein eingebetteter AC-Text).
- **AC9** — **ADR-Durchleitung:** `adr`-Notizen (Nygard-Format) werden als eigene Themen-Notiz nach `docs/architecture/` durchgereicht (kein Zwang in eine Feature-Spec); Verweis in der betroffenen Spec unter Abhängigkeiten.
- **AC10** — **Drift-Erkennung:** Nachträgliche Änderungen an übernommenen PM-Quellnotizen werden über den bestehenden `sync_hash`-Mechanismus erkannt und von `--audit` bzw. `[[obsidian-sync]]` gemeldet — keine neue Mechanik.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace pm-import#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate.

## Verträge

**Mapping-Tabelle (pm-skills-Artefakt → Fabrik-Ziel):**

| Quelle (pm-skills) | Ziel | Transformation |
|---|---|---|
| `problem-statement` | Spec «Zweck» | auf 1–2 Sätze verdichtet; Langfassung → `docs/concept.md` |
| `prd`: Ziele | Spec «Zweck» (ergänzend) | mit Problem-Statement zusammengeführt |
| `prd`: Non-Goals | Spec «Nicht-Ziele» | 1:1 |
| `prd`: Scope | Spec «Verträge» + «Abhängigkeiten» | Scope-Elemente aufteilen |
| `prd`: Risiken | `docs/concept.md` + Fragenkatalog | kein Spec-Feld (AC5) |
| `hypothesis` | `BR-NNN`-Kandidat (`architecture.md`/`data-model.md`) | Spec referenziert `(→ BR-NNN)` (AC3) |
| `user-stories` | Spec «Main Success Scenario» + «Alternative Flows» | Story → Flow-Schritt; Flows optional, jede Story ⇒ ≥ 1 AC |
| `acceptance-criteria` (GWT) | Spec «Acceptance-Kriterien» | AC4 |
| `edge-cases` | Spec «Edge-Cases & Fehlerverhalten» | 1:1 |
| `adr` | `docs/architecture/<thema>.md` | Durchleitung (AC9) |
| `launch-checklist` | Zerlege-Hinweise für Stufe c | AC8 |

**Frontmatter der erzeugten Spec:** exakt nach `templates/_docs/specs/_template.md` — `id` (feature-slug aus dem PRD-Titel, kebab-case, stabil), `title`, `status: draft`, `version: 1`, `spec_format`-Stempel aus der Vorlage, `area` via `requirement`-Intake (`[[requirement-area-intake]]`).

## Edge-Cases & Fehlerverhalten
- **E1:** Unvollständiges/mehrdeutiges PM-Artefakt → Fragenkatalog-Eintrag statt stillem Ideen-Pfad-Fallback.
- Kollidierender `id`-Slug mit bestehender Spec → Fragenkatalog (Zusammenführen vs. neuer Slug), nie stilles Überschreiben.
- pm-skills-Format-Änderungen (neue Template-Versionen upstream) → nicht erkannte Struktur fällt kontrolliert auf den Ideen-Pfad zurück (AC1), Klassifikations-Heuristik ist der einzige anzupassende Punkt.

## NFRs
- **Determinismus vor Eleganz:** definierte Zuordnung schlägt freie Interpretation; das Fragenkatalog-Gate bleibt das einzige Ventil für Unklarheit.
- **KISS:** keine neue Pipeline, kein neuer Befehl, keine Vault-Schreibzone über `obsidian-ingest` AC17 hinaus.

## Nicht-Ziele
- **Kein** Fork oder Umbau von pm-skills — das Plugin bleibt Vanilla; die Anpassung lebt vollständig fabrikseitig.
- **Kein** vierter Requirement-Weg — Erweiterung von `/agent-flow:from-notes`, kein neues Kommando.
- **Kein** Import von last30days-Recherche-Inhalten in Specs — Recherche-Briefs sind Kontext der Ideen-Ebene; höchstens Quellverweis unter Abhängigkeiten der Ziel-Spec.
- **Keine** Änderung an Stufe c, `requirement`-Item-Vertrag oder Board-Schema.

## Abhängigkeiten
- `[[obsidian-ingest]]` (Basis: Reader, Gates, ID-Kette, Stempel, `--audit`) · `[[obsidian-sync]]` (Drift) · `[[reconcile]]` (Rückkanal, Konzept-Anker nachziehen) · `[[requirement-area-intake]]` (`area`-Stempelung) · `[[spec-format-field]]` · `templates/_docs/specs/_template.md` · `agents/requirement.md`.
- Externe Quelle: pm-skills (`product-on-purpose/pm-skills`, Apache 2.0) — nur als Notiz-Produzent, keine Code-Abhängigkeit.
- Obsidian-Quelldokument des Entwurfs: `300 Projekte/Last30Days und PM/Mapping Schema PM zu Agent Flow.md` (AlexSecondBrain).
