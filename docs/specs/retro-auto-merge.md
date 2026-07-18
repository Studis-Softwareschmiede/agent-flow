---
id: retro-auto-merge
title: Retro-PRs mergen bei reviewer-PASS automatisch (Mensch-Approve entfällt)
status: active
version: 1
spec_format: use-case-2.0
area: lernen-retro
---

# Spec: Retro-Auto-Merge bei reviewer-PASS  (`retro-auto-merge`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Subsystem-Bindung.** Diese Spec ändert die Gate-Stufe aus `CONCEPT.md` §5 **nur für retro-PRs**: das Gate „(a) reviewer-Check **+** (c) Mensch-Approve" wird für retro zu „(a) reviewer-Check, dann Auto-Merge". PR-Mechanik, Ledger, Reversibilität (§5a) und Schutzgitter G1–G3 bleiben unverändert; G4 wandelt sich von „kein Auto-Merge" zu „Auto-Merge NUR nach reviewer-PASS".

## Zweck
Der Lernzyklus der Fabrik soll nicht am manuellen Owner-Approve hängen: nach einem erfolgreichen retro-Lauf wird der retro-PR vom `reviewer` geprüft und bei `Review-Gate: PASS` **automatisch gemerged**. Owner-Entscheid 2026-07-18. Der PR bleibt als Audit-Trail bestehen; Rückrollbarkeit (git revert + `LEARNINGS.md`-Status `Reverted`) bleibt das Sicherheitsnetz gegen schlechte Regeln.

## Main Success Scenario
1. `retro` schliesst einen Lauf ab (Modus A/B inkl. C/D/E) und öffnet wie bisher den PR gegen agent-flow (+ `LEARNINGS.md`-Zeile).
2. Direkt danach wird der `reviewer` über den PR-Diff dispatcht (Checkliste: Schutzgitter G1/G3-Konformität, Provenance G2, Sektions-Disziplin, Regel-IDs, Dedup).
3. `Review-Gate: PASS` → der Lauf merged den eigenen PR automatisch (squash) und meldet den Merge inkl. PR-Link.
4. `LEARNINGS.md`-Status der promoteten Zeilen wechselt wie bisher zu `Merged`; der Owner wird informiert, muss aber nicht handeln.

## Alternative Flows
### A1: CHANGES-REQUIRED
- Bei `Review-Gate: CHANGES-REQUIRED` wird **nicht** gemerged. Critical+Important-Befunde gehen als Arbeitsauftrag an den laufenden retro-Lauf zurück (max. 3 Iterationen, analog Kern-Loop); danach erneuter reviewer-Check. Schleifenschutz erschöpft → PR bleibt offen + Meldung an den Owner (heutiges Verhalten als Fallback).

### E1: Merge scheitert technisch
- Scheitert `gh pr merge` (Branch-Protection, Merge-Konflikt, Netz), bleibt der PR offen und der Lauf meldet den Grund sichtbar (Lauf-Output). Kein Retry-Loop über Gebühr, kein Direkt-Push auf `main` als Ausweichpfad.

## Acceptance-Kriterien

- **AC1** — Auto-Merge nach PASS: nach PR-Erstellung dispatcht der retro-Lauf den `reviewer` über den PR-Diff; bei `Review-Gate: PASS` wird der PR ohne Owner-Approve automatisch gemerged (squash, via bestehender gh-Auth). Der Merge + PR-Link werden im Lauf-Output gemeldet.
- **AC2** — Kein Merge ohne PASS: bei `CHANGES-REQUIRED` wird nicht gemerged; Befunde werden im Loop (max. 3 Iterationen) behoben und erneut geprüft. Bleibt das Gate rot, bleibt der PR offen + sichtbare Meldung an den Owner. *(deckt A1)*
- **AC3** — Technischer Fehlschlag sichtbar: scheitert der Merge trotz PASS (Protection/Konflikt/Netz), bleibt der PR offen; der Grund wird gemeldet; es gibt keinen Direkt-Push-Ausweichpfad. *(deckt E1)*
- **AC4** — Audit-Trail unverändert: PR-Body, `LEARNINGS.md`-Ledger (inkl. `Proposed → Merged`-Übergang) und der dokumentierte Revert-Pfad (`git revert` + Status `Reverted`) bleiben vollständig erhalten; der Auto-Merge ändert nur den Merge-Auslöser, nicht die Nachvollziehbarkeit.
- **AC5** — Scope nur retro: der Auto-Merge gilt für retro-PRs (Modus A/B/D/E inkl. Estimator-PRs E2). `train`-PRs und `teamLeader`-PRs behalten das bisherige Gate (reviewer-Check + Mensch-Approve) unverändert.
- **AC6** — Doku-Nachzug konsistent: `CONCEPT.md` §5 (Gate-Stufe, als retro-Ausnahme markiert), `AGENTS.md` (Abschnitt 5 retro: „merged eigenen PR NICHT" → angepasst), `agents/retro.md` (G4, PR-Mechanik Schritt 5, Harte Grenzen) und `skills/retro/SKILL.md` (Schutzgitter 4 + Abschluss-Zeile „Merge erst nach … deinem Approve") führen einheitlich die neue Semantik; kein widersprüchlicher „kein Auto-Merge"-Text für retro bleibt stehen.
- **AC7** — G4 bleibt ein Gate: der reviewer-Check ist weiterhin **zwingend** vor jedem Merge (kein Merge ohne dispatchten reviewer mit PASS); der Auto-Merge entfernt ausschliesslich das Mensch-Approve, nicht die Prüfung.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace retro-auto-merge#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.
> Da es sich um Konzept-/Agent-Def-/Skill-Text handelt (`language: md`), erfolgt die Abnahme
> als Doku-Inspektion (analog `retro-g1-owner-override`).

## Verträge

### Gate-Semantik retro-PR (ersetzt für retro die §5-Stufe „reviewer + Mensch-Approve")
| Zustand | Verhalten |
|---|---|
| reviewer PASS | Auto-Merge (squash) + Meldung. |
| reviewer CHANGES-REQUIRED | Fix-Loop (≤ 3 Iterationen) → erneuter Check; danach offen + Meldung. |
| Merge-Fehler trotz PASS | PR bleibt offen + Grund gemeldet; kein Direkt-Push. |
| Kein reviewer dispatchbar | Kein Merge — PR bleibt offen + Meldung (Fallback = heutiges Verhalten). |

## Edge-Cases & Fehlerverhalten
- **Leerer Lauf (kein PR):** nichts zu mergen, Verhalten unverändert.
- **PR enthält Agent-Def-Änderungen:** auch die laufen unter dem retro-Auto-Merge (Owner-Entscheid „alles auto bei PASS"); der reviewer prüft Agent-Def-Diffs mit derselben Strenge (G2-Provenance).
- **Parallel offener älterer retro-PR:** wird nicht automatisch nachgemerged — Auto-Merge gilt nur für den PR des laufenden Laufs.

## NFRs
- Nachvollziehbarkeit: jeder automatische Merge ist über PR + Ledger-Zeile auffindbar; der Owner kann jederzeit per `git revert` zurückrollen (§5a Reversibilität).
- Kein neuer Bypass: der Weg „Branch → PR → reviewer → merge" bleibt der einzige Schreibpfad in die Fabrik (NIE Direkt-Push auf `main`).

## Nicht-Ziele
- **Keine** Änderung am `train`-/`teamLeader`-Gate (bleibt reviewer-Check + Mensch-Approve).
- **Keine** Änderung an G1/G2/G3 oder an der PR-Mechanik (mktemp-Klon, Branch, LEARNINGS-Zeile).
- **Kein** Auto-Merge bei rotem oder fehlendem reviewer-Gate — G4 wird nicht entfernt, nur das Mensch-Approve.

## Abhängigkeiten
- `CONCEPT.md` §5 (Gate-Stufen) + §5a (Observability/Reversibilität) — Ort des Gate-Entscheids.
- `agents/retro.md` (PR-Mechanik, G4, Harte Grenzen), `agents/reviewer.md` (Checkliste für retro-PRs), `skills/retro/SKILL.md`.
- [[retro-g1-owner-override]] — Schwester-Spec am selben Gate (G1); unberührt, aber der reviewer prüft beide Semantiken im selben Check.
- Entscheidungsquelle: Owner-Entscheid 2026-07-18 (Dialog-Session, „alles auto bei reviewer-PASS").
