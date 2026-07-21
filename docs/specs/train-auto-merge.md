---
id: train-auto-merge
title: train-Auto-Merge — reviewer-PASS mergt train-PRs automatisch (Owner-Entscheid 2026-07-21)
status: active
area: wissen-packs
version: 1
spec_format: use-case-2.0
---

# Spec: train-Auto-Merge  (`train-auto-merge`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut daraus), `tester` (prüft die AC), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck

**Owner-Entscheid 2026-07-21:** Nach Abschluss eines `/train`-Laufs sollen die Pack-PRs **ohne menschliches Drüberschauen** in `main` landen. Analog zur bestehenden retro-Ausnahme (`[[retro-auto-merge]]`, Owner-Entscheid 2026-07-18) entfällt für reguläre train-Pack-PRs die Gate-Stufe (c) Mensch-Approve; Stufe (a) `reviewer`-Check bleibt **zwingend** — kein Merge ohne `PASS`. Anlass: der Sammel-Lauf vom 2026-07-21 (27 Pack-PRs) blieb liegen, bis der Owner jeden PR einzeln freigab; zusätzlich mussten 23 der 27 PRs wegen `LEARNINGS.md`-Append-Konflikten manuell nachgemergt werden.

## Main Success Scenario
1. Ein train-Agent hat seinen Pack-PR geöffnet (Einzel- oder Mehr-Pack-Pfad).
2. Der Skill dispatcht den `reviewer` mit dem PR-Diff + den train-Verträgen als Prüfmaßstab.
3. `Review-Gate: PASS` → der Skill aktualisiert den Branch gegen `main`, mergt den PR automatisch (squash) und löscht den Branch.
4. Die Sammel-Übersicht (Mehr-Pack) bzw. die Abschluss-Meldung (Einzel-Pack) weist den Merge-Status je PR aus.

## Alternative Flows
### A1: CHANGES-REQUIRED
- Critical+Important gehen als Arbeitsauftrag an den train-Agenten zurück (Fix-Loop, max. 3 Iterationen — analog `[[retro-auto-merge]]`). Danach immer noch kein PASS → PR bleibt **offen** + Meldung an den Owner (kein Merge, kein stilles Verwerfen).

### E1: Merge schlägt trotz PASS fehl (Konflikt/Race)
- Branch gegen `main` aktualisieren (Union-Mechanik für den Ledger, AC5) und **einmal** erneut mergen; schlägt auch das fehl → PR bleibt offen + Meldung mit Grund.

## Acceptance-Kriterien

- **AC1 — reviewer-Gate-Dispatch im Skill.** `skills/train/SKILL.md`: Nach jedem geöffneten train-Pack-PR (Einzel- wie Mehr-Pack-Pfad) dispatcht der Skill den `reviewer` mit dem PR-Diff. Prüfmaßstab (mindestens): jede neue/geänderte Regel hat autoritative Quelle (Link) + stabile Regel-ID; max. 3 Regeln/Lauf; bei Framework-/Build-/Migrations-Packs ausschließlich Sektion `## A. Stable API & Deprecations` verändert; `LEARNINGS.md`-Zeile vorhanden; keine Halluzinations-Indizien (Regel ohne Quelle = Critical).
- **AC2 — Auto-Merge bei PASS.** `Review-Gate: PASS` → der Skill mergt den PR automatisch (squash) und löscht den Branch — **ohne** Mensch-Approve. `CONCEPT.md` §5 wird im selben Umsetzungs-PR um den Owner-Entscheid 2026-07-21 erweitert (train-Ausnahme analog der dokumentierten retro-Ausnahme; `teamLeader` behält das volle Gate).
- **AC3 — Fix-Loop bei CHANGES-REQUIRED.** Critical+Important → zurück an den train-Agenten, max. 3 Iterationen; danach ohne PASS bleibt der PR offen + explizite Meldung an den Owner (→ A1). Kein Merge ohne PASS — die Stufe (a) ist nicht abschaltbar.
- **AC4 — Mehr-Pack-Fan-out integriert.** Beim parallelen Fan-out läuft Review+Merge **je PR** unabhängig (kein Sammel-Gate); die Sammel-Übersicht wird um den Merge-Status erweitert: `gemergt (#PR)` | `offen: CHANGES-REQUIRED nach 3 Iterationen` | `offen: Merge-Fehler <Grund>`.
- **AC5 — Ledger-Konflikt-Härtung.** `LEARNINGS.md` erhält in `.gitattributes` die Merge-Strategie `union` (append-only Ledger — parallele train-PRs hängen je eine Zeile an; Vorfall 2026-07-21: 23/27 PRs mit Append-Konflikt). Zusätzlich aktualisiert der Skill den PR-Branch unmittelbar vor dem Merge gegen `main` (→ E1).
- **AC6 — Sondermodi behalten das Mensch-Gate.** `model-tiers` (steuert die Modell-Matrix ALLER Agent-Dispatches) und `--bootstrap` (legt neue Packs an) bleiben bei der bisherigen Gate-Stufe (a) + (c) — der Auto-Merge gilt **nur** für reguläre Pack-Update-PRs. Die jeweiligen Spec-/Doku-Stellen (`[[model-tier-curator]]`, `[[train-bootstrap-new-pack]]`) bleiben unverändert.

## Verträge
- Betroffen: `skills/train/SKILL.md` (Gate-Dispatch, Merge-Schritt, Sammel-Übersicht), `agents/train.md` (Fix-Loop-Empfang analog retro), `.gitattributes` (union für `LEARNINGS.md`), `CONCEPT.md` §5 (Owner-Entscheid dokumentieren). Kein Eingriff in `retro`-Mechanik.
- Der reviewer-Check läuft als regulärer Agent-Dispatch (kein GitHub-Required-Check) — Merge-Ausführung via `gh pr merge --squash --delete-branch`.

## Edge-Cases & Fehlerverhalten
- **E2 — reviewer-Dispatch schlägt technisch fehl** (kein Ergebnis): kein Merge, PR bleibt offen + Meldung — Fail-Safe Richtung „offen lassen", nie Richtung „ungeprüft mergen".
- **E3 — PR bereits gemergt/geschlossen** (Race mit manuellem Eingriff): als solcher in der Übersicht ausweisen, kein Fehler.

## NFRs
- Kein neues Tooling; Mehraufwand pro Pack-PR = 1 reviewer-Dispatch. Fail-Safe-Prinzip: jeder Zweifel endet in „PR offen + Meldung", nie in einem ungeprüften Merge.

## Nicht-Ziele
- **Keine** Abschaffung der Gate-Stufe (a) — reviewer-PASS bleibt Merge-Bedingung.
- **Keine** Änderung an `retro`-/`teamLeader`-Gates.
- **Kein** Auto-Merge für `model-tiers`/`--bootstrap` (AC6).

## Abhängigkeiten
- `[[retro-auto-merge]]` (Vorbild-Mechanik: PASS→Squash-Merge, Fix-Loop max. 3).
- CONCEPT.md §5 (Gate-Doktrin — wird um die train-Ausnahme erweitert, AC2).
