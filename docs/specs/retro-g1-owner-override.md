---
id: retro-g1-owner-override
title: Owner-Override der retro-Frequenz-Schwelle (G1) formell kodifizieren
status: active
area: lernen-retro
version: 1
spec_format: use-case-2.0
---

# Spec: Owner-Override der retro-Frequenz-Schwelle (G1)  (`retro-g1-owner-override`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Kodifiziert einen **formellen, eng begrenzten Owner-Override-Pfad** für Schutzgitter #1 (G1, Frequenz-Schwelle) der `retro`-Promotion. G1 verlangt heute HART, dass ein Pattern in **≥2 verschiedenen Projekten** × **≥2 Code-Stellen** vorkommt, bevor `retro` es in einen Framework-/Build-Pack (oder eine Agent-Def) promoten darf (`docs/architecture/framework-build-subsystem.md` §9 Schutzgitter #1; `agents/retro.md` markiert G1-Verstöße pauschal als Critical, `retro/G1-Violation`). **Realer Vorfall (2026-07-14):** die erste Owner-genehmigte Promotion trotz unerfüllter G1-Schwelle (Regel `alembic/B01`) — Begründung: ki-investment ist org-weit das **einzige** Postgres-Projekt, die „≥2 Projekte"-Schwelle war damit **strukturell unerfüllbar**, obwohl 6 unabhängige Vorfälle in *einem* Projekt vorlagen. Dieser Override existiert bisher nur als Freitext-Prosa im PR-Body von `agent-flow#335`; weder §9 noch `agents/retro.md`/`skills/retro` kennen einen Ausnahmepfad. Diese Spec ergänzt §9 (+ `agents/retro.md` + `skills/retro`) um einen **kodifizierten** Override mit vier harten Bedingungen, sodass künftige Overrides einem prüfbaren Pfad folgen statt Einzelfall-Prosa zu sein, und das `reviewer`-Gate die vier Bedingungen **prüft**, statt einen G1-„Verstoß" pauschal als Critical zu werfen.

## Main Success Scenario
1. `retro` findet ein generalisierbares Pattern, das G1 (≥2 Projekte × ≥2 Stellen) **nicht** regulär erfüllt, weil die „≥2 Projekte"-Bedingung **strukturell unerfüllbar** ist (das Pattern lebt in der einzigen Projektklasse ihrer Art — z.B. das einzige Postgres-Projekt der Org).
2. Es liegen **≥4 unabhängige Belegstellen in einem Projekt** vor (Datei/Zeile oder PR-Nummer — strenger als die reguläre „≥2 Stellen").
3. Ein **explizites, datiertes Owner-Approval** für genau diese Promotion existiert.
4. `retro` erstellt den Pack-/Agent-Def-PR mit einem **standardisierten PR-Body-Abschnitt** „Owner-Approved G1-Override" (die vier Bedingungen a–d ausgefüllt) und kennzeichnet die Promotion in `LEARNINGS.md` als „Owner-Approved G1-Override".
5. Das `reviewer`-Gate erkennt den Override-Abschnitt, **prüft die vier Bedingungen** und lässt die Promotion passieren, wenn alle vier erfüllt + belegt sind — statt einen pauschalen `retro/G1-Violation`-Critical zu werfen.

## Alternative Flows
### A1: Override-Bedingung nicht erfüllt
- Fehlt eine der vier Bedingungen (a strukturelle Unerfüllbarkeit nicht begründet, b < 4 Belegstellen, c kein datiertes Owner-Approval, d PR-Body-Abschnitt/LEARNINGS-Kennzeichnung unvollständig), bleibt es beim regulären G1-Gate: `reviewer` wirft `retro/G1-Violation` (Critical) → `CHANGES-REQUIRED`. Der Override ist **kein** Freibrief, sondern ein an vier belegte Bedingungen gebundener Ausnahmepfad.

### A2: Kein Override beansprucht (Regelfall)
- Beansprucht ein retro-PR **keinen** Override-Abschnitt, gilt G1 **unverändert** hart (≥2 Projekte × ≥2 Stellen; Single-Projekt-Kandidaten → `Proposed`-Wartezimmer). Der neue Pfad ändert das Standardverhalten **nicht** — er ist opt-in und muss explizit beansprucht + belegt werden.

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

- **AC1** — §9-Ausnahmepfad dokumentiert: `docs/architecture/framework-build-subsystem.md` §9 Schutzgitter #1 wird um einen **Owner-Override-Pfad** ergänzt, der die vier Bedingungen (a) strukturelle G1-Unerfüllbarkeit begründet (z.B. einziges Projekt seiner Klasse), (b) **≥4 unabhängige Belegstellen in einem Projekt**, (c) explizites, **datiertes** Owner-Approval, (d) standardisierter PR-Body-Abschnitt + `LEARNINGS.md`-Kennzeichnung „Owner-Approved G1-Override" **kanonisch und bindend** benennt. Der Pfad ist als eng begrenzte Ausnahme markiert, nicht als Aufweichung des Default-G1.
- **AC2** — `agents/retro.md` Override-Handhabung: die Agent-Def beschreibt, wann und wie `retro` den Override beansprucht — die vier Bedingungen prüfen, den standardisierten PR-Body-Abschnitt erzeugen und die `LEARNINGS.md`-Zeile als „Owner-Approved G1-Override" kennzeichnen. Ohne erfüllte Bedingungen bleibt G1 hart (kein eigenmächtiger Bypass durch `retro`).
- **AC3** — `reviewer`-Gate prüft statt pauschal Critical: `agents/retro.md`/`agents/reviewer.md` legen fest, dass bei beanspruchtem Override das Gate die **vier Bedingungen** prüft (a–d belegt/vorhanden) und die Promotion bei Vollständigkeit **passieren lässt**; nur bei **fehlender/unvollständiger** Bedingung wird `retro/G1-Violation` (Critical) geworfen. Der bisherige pauschale „G1 unerfüllt → immer Critical"-Automatismus gilt für beanspruchte, vollständig belegte Overrides **nicht** mehr. *(deckt A1)*
- **AC4** — Standardisierter PR-Body-Abschnitt: es existiert eine **kanonische Vorlage** des Abschnitts „Owner-Approved G1-Override" mit den vier ausfüllbaren Feldern (a Unerfüllbarkeits-Begründung, b Liste der ≥4 Belegstellen, c Datum + Referenz des Owner-Approvals, d Bestätigung der LEARNINGS-Kennzeichnung). `agents/retro.md` und `skills/retro/SKILL.md` referenzieren dieselbe Vorlage (Single Source of Truth, kein Format-Drift).
- **AC5** — `skills/retro` Sichtbarkeit: `skills/retro/SKILL.md` benennt den Override-Pfad in seiner G1-Beschreibung (heute: „Promotion nur bei ≥2 Projekten × ≥2 Stellen") als eng begrenzte, an vier Bedingungen gebundene Ausnahme — kein widersprüchlicher „immer hart"-Text bleibt stehen.
- **AC6** — Präzedenzfall referenziert: der kodifizierte Pfad nennt `agent-flow#335` (Regel `alembic/B01`, ki-investment als einziges Postgres-Projekt) explizit als **ersten** Eintrag/Beispiel des Override-Registers — in §9 und/oder in der `LEARNINGS.md`-Kennzeichnung, damit die Herkunft der Regel nachvollziehbar bleibt.
- **AC7** — Sonar-G1 & Estimator-G1 unberührt: der bestehende `G1-Sonar`-Pfad (§9a/H3, `≥2 Repos` ODER `≥5× in 1 Repo`) und die G1-Freistellung für Estimator-PRs (Modus E) bleiben **unverändert** — diese Spec ergänzt ausschließlich den Owner-Override für den Lessons-Pfad (Modus A) und definiert für die anderen Quellen nichts neu.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace retro-g1-owner-override#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.
> Da es sich um Architektur-/Agent-Def-/Skill-Text handelt (`language: md`), erfolgt die Abnahme
> als Doku-Inspektion (analog `spec-auto-activation` AC5, `lessons-writeback-coverage`).

## Verträge

### Vier Override-Bedingungen (kanonisch, alle vier HART)
Ein Owner-Override von G1 ist **nur** gültig, wenn **alle vier** belegt sind:
- **(a) Strukturelle Unerfüllbarkeit** — begründet, warum die „≥2 Projekte"-Schwelle nicht erreichbar ist (z.B. einziges Projekt seiner Klasse in der Org). Bloße Neuheit oder „noch kein Zweitprojekt aufgetaucht" genügt **nicht**.
- **(b) Mindest-Belegzahl** — **≥4 unabhängige Belegstellen in einem Projekt** (Datei/Zeile oder PR-Nummer), namentlich gelistet (strenger als reguläre „≥2 Stellen").
- **(c) Datiertes Owner-Approval** — explizit, mit Datum + auffindbarer Referenz (z.B. PR-Kommentar/Issue).
- **(d) Standardisierter Nachweis** — PR-Body-Abschnitt „Owner-Approved G1-Override" (Vorlage, AC4) ausgefüllt **und** `LEARNINGS.md`-Zeile mit dem Vermerk „Owner-Approved G1-Override" gekennzeichnet.

### PR-Body-Abschnitt (kanonische Vorlage — Single Source of Truth für `agents/retro.md` + `skills/retro`)
```markdown
### Owner-Approved G1-Override
- (a) Strukturelle Unerfüllbarkeit: <Begründung, z.B. einziges Postgres-Projekt der Org>
- (b) Belegstellen (≥4, ein Projekt): <Datei:Zeile | PR-#, …>
- (c) Owner-Approval: <YYYY-MM-DD> — <Referenz (PR-Kommentar/Issue)>
- (d) LEARNINGS.md gekennzeichnet: ja/nein (Zeile: „… — Owner-Approved G1-Override")
- Präzedenz: agent-flow#335 (alembic/B01)   # erster Eintrag des Registers
```

### Reviewer-Gate-Semantik
- Beanspruchter Override + alle vier Bedingungen belegt → Gate **passt** (kein `retro/G1-Violation`).
- Beanspruchter Override + ≥1 Bedingung fehlt/unvollständig → `retro/G1-Violation` (Critical) → `CHANGES-REQUIRED`.
- **Kein** beanspruchter Override → reguläres G1 unverändert hart (Default, A2).

## Edge-Cases & Fehlerverhalten
- **Override beansprucht, aber Sonar-Quelle (Modus B):** irrelevant — Sonar nutzt `G1-Sonar` (H3), nicht den Lessons-G1; der Owner-Override greift nur im Lessons-Pfad (Modus A) (AC7).
- **Owner-Approval nachträglich/undatiert:** ohne Datum + Referenz ist (c) unerfüllt → Gate wirft Critical (A1). Keine „mündliche"/implizite Zustimmung.
- **Weniger als 4 Belegstellen, aber sehr eindeutig:** kein Override — bei < 4 Stellen bleibt es beim `Proposed`-Wartezimmer bzw. regulärem G1 (bewusst konservativ gewählte Schwelle).
- **Mehrere Overrides im selben PR:** jeder braucht seinen eigenen ausgefüllten Abschnitt (a–d); ein gemeinsamer Sammel-Abschnitt für mehrere Regeln ist unzulässig (Nachvollziehbarkeit je Regel).

## NFRs
- Nachvollziehbarkeit/Audit: jeder Override ist über den standardisierten PR-Body-Abschnitt + die `LEARNINGS.md`-Kennzeichnung dauerhaft belegt (kein Freitext-Einzelfall mehr).
- Konservativ by default: der Pfad ist opt-in, eng begrenzt (vier harte Bedingungen) und lässt das Default-G1 unangetastet — Minimierung des Fehl-Generalisierungs-Risikos, das Schutzgitter #1 ursprünglich adressiert.

## Nicht-Ziele
- **Keine** Aufweichung des Default-G1: ohne beanspruchten, vollständig belegten Override gilt „≥2 Projekte × ≥2 Stellen" unverändert (A2).
- **Keine** Änderung an `G1-Sonar` (H3) oder der Estimator-G1-Freistellung (Modus E) (AC7).
- **Kein** Auto-Merge / Bypass des reviewer-Gates (Schutzgitter #4 bleibt) — der Override ändert nur, **welche** Bedingung das Gate prüft, nicht **ob** es prüft.
- **Keine** automatische Owner-Approval-Erteilung durch `retro` — das Approval ist und bleibt eine explizite Owner-Handlung.

## Abhängigkeiten
- `docs/architecture/framework-build-subsystem.md` §9 (Schutzgitter #1) — Ort des kodifizierten Ausnahmepfads (AC1).
- `agents/retro.md` (Frequenz-Schwelle G1, Schritt 2; `retro/G1-Violation`), `agents/reviewer.md` (Gate-Semantik), `skills/retro/SKILL.md` (G1-Beschreibung) — Konsumenten/Umsetzungsstellen (AC2/AC3/AC5).
- `[[retro-cooldown-persistence]]` — Schwester-Schutzgitter (G3); dieses Muster (Schutzgitter formal + Spec) dient als Vorbild für die G1-Kodifizierung.
- Präzedenzfall/Entscheidungsquelle: `agent-flow#335` (Regel `alembic/B01`), Owner-Approval 2026-07-14.
