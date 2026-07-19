---
id: admin-bereich-manifest-intake
title: Admin-Bereich-Manifest-Intake — requirement fragt bei App-Erstellung die Manifest-Parameter
status: active
version: 1
spec_format: use-case-2.0
area: anforderung-intake
---

# Spec: Admin-Bereich-Manifest-Intake  (`admin-bereich-manifest-intake`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut die Frage in den requirement-Pfad), `reviewer` (Drift-Gate), `tester` (prüft die AC).
>
> **Subsystem-Bindung.** Verankert die **requirement-Frage** des Fabrik-Standards Admin-Bereich (`docs/architecture/admin-bereich-subsystem.md` §7): bei der Erstellung eines UI-Projekts fragt `requirement`, welche Parameter ins Admin-Manifest sollen (Startbestand: `.env`-Keys).

## Zweck

Das Admin-Manifest (`config/admin-manifest.yaml`) bestimmt, welche Parameter die generische Admin-UI anzeigt/editiert. Diese Spec ergänzt den `requirement`-Pfad um eine gezielte Frage bei App-Erstellung, welche Parameter ins Manifest aufgenommen werden — mit den vorhandenen `.env`-Keys als Startbestand — und füllt daraus die gescaffoldete Manifest-Vorlage.

## Kontext / Designnuancen (bindend)

- **Nur UI-Projekte** (GE7): die Frage wird nur bei UI-Projekten gestellt (nur dort existiert ein Admin-Bereich).
- **Startbestand = `.env`-Keys:** die Frage schlägt die vorhandenen `.env`-Keys als Ausgangs-Parameterliste vor.
- **Autonomie:** ohne Owner-Antwort (autonomer Lauf) greift ein konservativer Default statt Blockade.

## Main Success Scenario

1. `requirement` läuft bei der Erstellung eines UI-Projekts.
2. Es fragt (AskUserQuestion), welche Parameter ins Admin-Manifest sollen — Startbestand: die vorhandenen `.env`-Keys.
3. Die Antwort füllt die gescaffoldete `config/admin-manifest.yaml` im Manifest-Vertrag (→ BR-011).

## Alternative Flows

### A1: autonomer Lauf / keine Antwort
- Ohne Owner-Antwort füllt `requirement` das Manifest konservativ: alle `.env`-Keys als `editierbar: false`, Secret-Namensmuster (`*_KEY`, `*_TOKEN`, `*_SECRET`, `*_PASSWORD*`, `*_URL`) als `secret: true`; Verfeinerung erfolgt später projekt-lokal.

## Acceptance-Kriterien

- **AC1** — Bei der Erstellung eines **UI-Projekts** fragt `requirement` (AskUserQuestion), welche Parameter ins Admin-Manifest sollen; der Vorschlags-Startbestand sind die vorhandenen `.env`-Keys. Bei Nicht-UI-Projekten entfällt die Frage.
- **AC2** — Die Antwort füllt die gescaffoldete `config/admin-manifest.yaml` im Manifest-Vertrag: pro Parameter `key`, `quelle`, `typ`, `editierbar`, `secret`/`maskiert`, `validierung` (→ BR-011).
- **AC3** — Im **autonomen Lauf ohne Antwort** greift der konservative Default (alle `.env`-Keys `editierbar: false`; Secret-Namensmuster `secret: true`) statt einer Blockade (→ BR-007, BR-008). *(deckt A1)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace admin-bereich-manifest-intake#AC<n>[,BR-NNN]`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate.
> Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

### Manifest-Befüllung
```
Startbestand:  .env-Keys (Vorschlag)
Ziel:          config/admin-manifest.yaml (Manifest-Vertrag BR-011)
Default (autonom): editierbar:false; Secret-Namensmuster ⇒ secret:true
```

**Feld-Defaults (beide Pfade, Owner-Antwort wie autonom):** `quelle: env`; `typ: secret` bei Secret-Namensmuster (`*_KEY`, `*_TOKEN`, `*_SECRET`, `*_PASSWORD*`, `*_URL`), sonst `typ: string`; `editierbar: false`; `secret: true` bei Secret-Namensmuster, sonst `false`; `validierung` leer (Verfeinerung projekt-lokal). Die Owner-Antwort bestimmt ausschliesslich, **welche** `.env`-Keys als Parameter aufgenommen werden — nicht die Feld-Werte selbst.

## Edge-Cases & Fehlerverhalten

- **Kein `.env`/keine Keys vorhanden** → leeres Manifest-Gerüst mit Vertrags-Kommentar; Parameter kommen später projekt-lokal dazu.
- **Nicht-UI-Projekt** → keine Frage, kein Manifest (GE7).

## NFRs

- **Autonomie:** kein Blockieren ohne Owner — konservativer Default greift.

## Nicht-Ziele

- Die Manifest-Vorlage/das Scaffold selbst ([[admin-bereich-scaffolding]]).
- Das Bereichs-Eingangs-Gate von requirement ([[requirement-area-intake]]) — unverändert.

## Abhängigkeiten

- `docs/architecture/admin-bereich-subsystem.md` §7, BR-011 — requirement-Frage + Manifest-Vertrag.
- [[admin-bereich-scaffolding]] — liefert die zu füllende Manifest-Vorlage.
- `agents/requirement.md` — der Agent, in den die Frage eingebaut wird.
