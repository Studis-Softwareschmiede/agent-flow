---
id: test-scope-per-role
title: Test-Umfang je Rolle — Coder targeted, Tester voll
status: active
version: 1
spec_format: use-case-2.0
area: rollen-agenten
---

# Spec: Test-Umfang je Rolle — Coder targeted, Tester voll  (`test-scope-per-role`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für die Rollen-Agenten `coder` (`agents/coder.md`) und `tester` (`agents/tester.md`): wer welchen Test-Umfang je Story fährt.

## Zweck
Trennt den Test-Umfang der Fabrik-Rollen, damit pro Story genau **ein** garantierter voller Suite-Durchlauf entsteht statt zwei: der `coder` fährt beim Selbsttest während der Implementierung nur die vom Diff **betroffenen** Tests + Lint (schnelles Feedback), der `tester` fährt im Abschluss-Gate weiterhin die **volle** Suite + Build + Smoke + volle Lint. Netto: schnelleres Coder-Feedback, keine Doppel-Suite, aber keine Aufweichung der einzigen garantierten Vollprüfung.

## Acceptance-Kriterien

- **AC1** — `agents/coder.md` (Self-Test-Schritt) schreibt vor: Der `coder` fährt beim Selbsttest während der Implementierung **nur die vom Diff betroffenen Tests + Lint auf den geänderten Dateien**, **nicht** die komplette Suite. „Betroffen" ist pragmatisch definiert: die Tests der geänderten Module/Bereiche zzgl. Lint auf den geänderten Dateien. Sind diese betroffenen Tests oder der Lint rot → fixen, **nicht** übergeben (die bestehende Fix-vor-Handoff-Pflicht bleibt erhalten).
- **AC2** — `agents/tester.md` (Vorgehen) schreibt vor: Das Tester-Gate fährt **weiterhin die volle Test-Suite + Build + Smoke** — im Umfang unverändert. Der Tester begrenzt seinen Test-Lauf **nicht** auf die vom Diff betroffenen Tests.
- **AC3** — `agents/tester.md` schreibt zusätzlich explizit vor: Der Tester fährt **die volle Lint** (nicht nur die geänderten Dateien) als Teil des Gates, damit Lint-Fehler nicht erst in der GitHub-CI auffallen.
- **AC4** — Die Rollen-Contracts halten die Netto-Invariante fest: **pro Story genau ein garantierter voller Suite-Durchlauf** (im Tester-Gate). Der Tester ist die **einzige** Stelle, die die volle Suite garantiert; dieser Umfang darf **nicht** aufgeweicht oder auf „nur betroffene Tests" reduziert werden. (Harte Lehre aus S-322, 2026-07-08: targeted-only Tests waren grün, die volle CI aber rot wegen einer Async-Race.)
- **AC5** — Die volle Suite wird **nicht** ans Feature-Ende verschoben: sie bleibt **pro Story** im Tester-Gate. Weder `agents/coder.md` noch `agents/tester.md` führen einen Feature-End-Sammellauf als Ersatz für den Story-weisen Tester-Volllauf ein.

> **Traceability:** Da `language: md` im `agent-flow`-Repo (No-Op-Build/-Test/-Lint), sind die „Tests" hier Doku-Diffs an den Agenten-Definitionen — der `tester` behandelt reine Doku-Diffs als `SKIPPED-DOC-ONLY`. In konsumierenden Projekten mit echter Toolchain sind AC1–AC5 gegen die dortigen Test-/Lint-Befehle wirksam.

## Verträge
- **Betroffene Dateien:** `agents/coder.md` (Self-Test), `agents/tester.md` (Vorgehen: Test-Stufe + neue Lint-Stufe).
- **Coder-Selbsttest:** betroffene Tests (geänderte Module/Bereiche) + Lint auf geänderten Dateien; Rot → Fix, kein Handoff.
- **Tester-Gate:** volle Suite + Build + Smoke + volle Lint; Umfang der bestehenden Stufen (Build-Tool-Dispatch, Security-Smoke, DB-Subsystem-Smoke) unverändert.

## Edge-Cases & Fehlerverhalten
- **No-Op-Toolchain (`profile.test`/`lint` = `true`/`none`):** Beide Rollen reduzieren auf No-Op; die Umfangs-Trennung ist dann leer wirksam, der Contract-Text bleibt gültig.
- **Reine Doku-Diffs:** unverändert `SKIPPED-DOC-ONLY` im Tester (keine Suite nötig).
- **Coder-Selbsttest grün, aber volle Suite rot:** genau der von AC4 abgedeckte Fall — das Tester-Gate fängt ihn ab (FAIL → zurück an `coder`); der targeted-Lauf des Coders ist bewusst kein Vollbeleg.

## NFRs
- **Durchsatz:** Ziel ist ein voller Suite-Durchlauf je Story statt zwei; das Coder-Feedback wird schneller, ohne die Gate-Garantie zu schwächen.

## Nicht-Ziele
- Keine Verschiebung der vollen Suite ans Feature-Ende.
- Keine Aufweichung des Tester-Gates auf targeted-only Tests.
- Keine Änderung der übrigen Tester-Stufen (Security-Smoke, DB-Subsystem-Smoke, AC-Abgleich).

## Abhängigkeiten
- Rollen-Agenten `agents/coder.md`, `agents/tester.md`.
