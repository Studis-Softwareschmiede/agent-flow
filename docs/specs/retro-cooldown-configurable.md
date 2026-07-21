---
id: retro-cooldown-configurable
title: Retro-Cooldown konfigurierbar (retro_cooldown_days, Default 1 Tag)
status: active
version: 1
spec_format: use-case-2.0
area: lernen-retro
---

# Spec: Retro-Cooldown konfigurierbar  (`retro-cooldown-configurable`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Subsystem-Bindung.** Diese Spec ändert **ausschliesslich die Schwelle** des Schutzgitters G3 (Cooldown, `docs/architecture/framework-build-subsystem.md` §9 Punkt 3): fix „7 Tage" wird zum konfigurierbaren Profil-Feld `retro_cooldown_days` mit **Default 1**. Stempel-Ort, Persistenz-Mechanik und `--force`-Semantik ([[retro-cooldown-persistence]]) bleiben unverändert.

## Zweck
In der Aufbauphase der Fabrik soll `retro` **öfter** laufen dürfen als 1×/Woche/Repo: schnellere Metrik-Aggregation (Modus C/E läuft bei jedem Lauf mit) und Lessons erreichen früher das Wartezimmer bzw. ihren Zweit-Beleg. Owner-Entscheid 2026-07-18: die Schwelle wird pro Projekt konfigurierbar (`retro_cooldown_days` im Projekt-Profil), Default **1 Tag** statt bisher fix 7 — später ohne Umbau wieder hochdrehbar.

## Acceptance-Kriterien

- **AC1** — Neues optionales Profil-Feld: `.claude/profile.md` (Frontmatter) des Projekt-Repos kennt das optionale Feld `retro_cooldown_days` (Ganzzahl ≥ 0, Einheit Tage). Einziger Konsument ist der G3-Cooldown-Check von `retro` (Schritt 3a).
- **AC2** — Default 1 Tag: fehlt das Feld oder ist es leer/unparsbar (keine Ganzzahl ≥ 0), gilt **1 Tag** als Default. Die bisherige fixe 7-Tage-Schwelle entfällt als Hardcode; wer 7 Tage will, setzt `retro_cooldown_days: 7` im Profil.
- **AC3** — G3-Check rechnet gegen das Feld: der Cooldown-Check in `agents/retro.md` (Schritt 3a) vergleicht das Stempel-Datum aus `.claude/lessons/.retro-last-run` gegen `retro_cooldown_days` statt gegen fixe 7 Tage. Stempel-Ort, Persistenz-Pfad (C4), Idempotenz und Fehlerverhalten aus [[retro-cooldown-persistence]] bleiben **unverändert**.
- **AC4** — Null-Wert = kein Cooldown: `retro_cooldown_days: 0` bedeutet „kein Cooldown" — jeder Lauf ist erlaubt; der Stempel wird trotzdem nach jedem erfolgreichen Lauf geschrieben + persistiert (Messbarkeit/Audit bleibt).
- **AC5** — `--force` unverändert: der manuelle Bypass umgeht den Cooldown wie bisher, unabhängig vom konfigurierten Wert.
- **AC6** — Doku-Nachzug konsistent: `agents/retro.md` (3a + Harte Grenzen G3), `skills/retro/SKILL.md` (Schutzgitter 3) und `docs/architecture/framework-build-subsystem.md` §9.3 nennen die neue konfigurierbare Schwelle einheitlich (Feldname, Default 1, 0-Semantik); kein widersprüchlicher „1×/Woche"-Text bleibt stehen. Die Profil-Vorlagen `templates/*/profile.md` dokumentieren das Feld als optionalen Kommentar (kein Pflicht-Eintrag).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace retro-cooldown-configurable#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.
> Da es sich um Agent-Def-/Skill-/Architektur-Text handelt (`language: md`), erfolgt die Abnahme
> als Doku-Inspektion (analog `retro-g1-owner-override`, `lessons-writeback-coverage`).

## Verträge

| Artefakt | Garantie |
|---|---|
| `.claude/profile.md` → `retro_cooldown_days` | Optionale Ganzzahl ≥ 0 (Tage). Fehlend/unparsbar ⇒ Default **1**. `0` ⇒ kein Cooldown. Einziger Konsument: `retro` G3-Check. |
| `agents/retro.md` (Schritt 3a / Harte Grenzen) | Cooldown-Formel: Lauf erlaubt, wenn kein parsbarer Stempel existiert ODER `heute − Stempel-Datum ≥ retro_cooldown_days`. Alles Übrige (Stempel-Write, C4-Persistenz, Meldung bei Push-Fehler) unverändert per [[retro-cooldown-persistence]]. |
| `skills/retro/SKILL.md` + `framework-build-subsystem.md` §9.3 | Dokumentieren dieselbe Schwelle/Semantik (Single Source of Truth, kein Format-Drift). |

## Edge-Cases & Fehlerverhalten
- **Negativer/nicht-numerischer Wert:** unparsbar ⇒ Default 1 (kein Abbruch, kein stiller 0-Fallback).
- **Stempel fehlt/leer/unparsbar:** wie bisher kein Cooldown, Lauf erlaubt ([[retro-cooldown-persistence]] V6).
- **`retro_cooldown_days` im agent-flow-Repo selbst:** gilt wie in jedem Projekt-Repo (Selbst-Dogfooding, kein Sonderpfad).

## NFRs
- Rückwärtskompatibel: bestehende Projekte ohne Feld ändern nur die effektive Schwelle (7 → 1), keinen Mechanismus.
- Kein zweiter State-Ort, kein zusätzlicher Bypass (konsistent mit `agents/retro.md` Harte Grenzen).

## Nicht-Ziele
- **Keine** Änderung an G1 (Frequenz-Schwelle ≥2 Projekte × ≥2 Stellen), G2 (Provenance) oder G4 (Reviewer-Gate) — G4-Änderung ist [[retro-auto-merge]].
- **Keine** Änderung an Stempel-Ort/-Persistenz ([[retro-cooldown-persistence]] bleibt maßgebend).
- **Keine** automatische Retro-Triggerung (wann retro läuft, entscheiden weiterhin Owner/äußere Schleife).

## Abhängigkeiten
- `docs/architecture/framework-build-subsystem.md` §9.3 (Schutzgitter G3) — Ort der Schwellen-Definition.
- [[retro-cooldown-persistence]] — Stempel-Mechanik, bleibt unverändert und wird von dieser Spec referenziert, nicht ersetzt.
- Entscheidungsquelle: Owner-Entscheid 2026-07-18 (Dialog-Session, „Retro öfter in der Aufbauphase").
