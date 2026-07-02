---
id: metrics-recording-reliability
title: Zuverlässige Metrik-Erfassung im /flow (Ledger-Lücken, ID-Format, Token)
status: draft
version: 1
---

# Spec: Zuverlässige Metrik-Erfassung im /flow  (`metrics-recording-reliability`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die ACs), `reviewer` (Drift-Gate).

## Zweck

Die Story-Detailansicht der GUI ([[../specs/story-detail-yaml-fallback]] in dev-gui) bleibt für aktuelle Stories leer, weil das Metrik-Ledger **gar nicht** befüllt wird. Diese Spec macht die Erfassung in `/flow` **zuverlässig**: jede erledigte Story hinterlässt eine `items.jsonl`-Zeile und ihre Dispatch-Zeilen, in **einheitlichem ID-Format**, mit befüllten **Tokens** — oder eine **sichtbare** Warnung, wenn nicht.

## Kontext / Befund (bindend)

Live verifiziert 2026-06-19 am dev-gui-Ledger:
- **Ledger-Lücken:** `dispatches.jsonl` endet 13.06., `items.jsonl` 16.06.; Stories ab ~16.06. (S-165 … S-171) haben **keine** Zeile. Grund: die Erfassung ist in `skills/flow/SKILL.md §2b` reine **best-effort-Prosa** mit `|| true` (K3 — jeder Fehler still verschluckt). Wird der Hand-Append-Schritt nicht ausgeführt, fehlt die Zeile **lautlos**.
- **ID-Format-Bruch:** §2b schreibt `item` als **Zahl** (`S-` strippen → int). Konsumenten (dev-gui `StoryMetricReader`) matchen aber den **String** `"S-165"`. Neuere Zeilen wurden teils schon als String `"S-139"` geschrieben → **uneinheitlich**.
- **Tokens nie befüllt:** `tok`/`tok_total` überall `null`. `scripts/metrics-collect.sh` patcht aus Subagent-Transcripts (`~/.claude/projects/<escaped-cwd>/.../subagents/agent-*.jsonl`); im GUI-/Container-Kontext greift der Pfad/`CLAUDE_CONFIG_DIR` offenbar nicht.

**Grenzen (Owner 2026-06-19):** Keine **Rückbefüllung** alter Stories (Flow/Startzeit nicht rekonstruierbar). Erfassung bleibt **deterministische Arithmetik** (~0 LLM-Token) und darf den Loop **nie** blockieren (K3 bleibt) — neu ist nur, dass die *Auslösung* strukturell und das *Fehlen* sichtbar wird.

## Verhalten

### V1 — Append als deterministischer Skript-Touchpoint
Die beiden §2b-Schritte werden in **Skripte** gebündelt, die `/flow` an den festen Touchpoints aufruft (statt jedes Mal frei jq-Zeilen hand­zuschreiben):
- nach jedem Agent-Dispatch → `scripts/metrics-append-dispatch.sh` (eine `dispatches.jsonl`-Zeile),
- beim Done (nach Rollout-Gate PASS) → `scripts/metrics-append-item.sh` (eine `items.jsonl`-Zeile + Rollup über die Dispatches des Items).
Der **Aufruf** ist damit nicht mehr optionale Prosa, sondern ein benannter, drift-armer Schritt. Intern weiter append-only und `|| true` (K3): ein Skript-Fehler stoppt den Loop nicht.

### V2 — Kanonisches ID-Format `S-###`
`item` wird in `dispatches.jsonl` **und** `items.jsonl` als **String** `S-###` geschrieben (identisch zur File-Board-ID), nicht als Zahl. Damit matchen Konsumenten ohne Sonderlogik. Alt-Zeilen (int) bleiben unangetastet (append-only); die Konsumenten-Toleranz dafür liegt dev-gui-seitig ([[../specs/story-detail-yaml-fallback]] V2).

### V3 — Token-Erfassung im GUI-/Container-Kontext
`metrics-collect.sh` muss die Subagent-Transcripts auch dann finden, wenn `/flow` aus der dev-gui-Session läuft: das verwendete Config-/Projekt-Verzeichnis (`CLAUDE_CONFIG_DIR` bzw. cwd-Escaping) wird korrekt aufgelöst bzw. als **Vorbedingung dokumentiert**. Schlägt das Auffinden fehl → `tok` bleibt `null` (kein Crash), aber V4 macht es sichtbar.

### V4 — Sichtbarkeits-Self-Check beim Done
Nach dem Done prüft `/flow`, ob für das Item eine `items.jsonl`-Zeile existiert (und ob `tok_total` befüllt ist). Fehlt die Zeile bzw. bleibt Token leer → **einmalige, sichtbare Notiz** im Lauf-Output (z.B. „Metrik für `S-165` nicht erfasst — Ledger-Zeile fehlt"). Die Lücke wird damit nicht mehr lautlos. Verändert **kein** Gate (K4).

## Acceptance-Kriterien

- **AC1** — Nach einem `/flow`-Done existiert für das Item genau eine `items.jsonl`-Zeile und je Dispatch eine `dispatches.jsonl`-Zeile; die Auslösung erfolgt über benannte Skript-Touchpoints (V1). *(V1)*
- **AC2** — `item` wird in beiden Ledgern als String `S-###` geschrieben (kanonisch), nicht als Zahl. *(V2)*
- **AC3** — Die Erfassung bleibt nicht-blockierend (K3): ein Append-/Collect-Fehler stoppt weder Loop noch verändert ein Gate. *(V1, V3)*
- **AC4** — `metrics-collect.sh` befüllt `tok`/`tok_total` auch im GUI-/Container-Kontext, ODER die nötige Vorbedingung (Config-/Pfad-Auflösung) ist dokumentiert und der Fehlerpfad bleibt `null`+kein Crash. *(V3)*
- **AC5** — Beim Done prüft `/flow` das Vorhandensein der Ledger-Zeile + Token und gibt bei Fehlen eine sichtbare, einmalige Notiz aus, ohne ein Gate zu ändern. *(V4)*
- **AC6** — Erfassung bleibt reine Datei-Arithmetik ohne zusätzlichen LLM-Aufruf (~0 Token). *(V1)*
- **AC7** — Keine Rückbefüllung/Umschreibung historischer Zeilen (append-only; int-Alt-Zeilen bleiben). *(Kontext)*

## Verträge

- **Skripte:** `scripts/metrics-append-dispatch.sh <story-id> <agent> <seq> <iter> <gate> <secs> [<cost_mode>]`, `scripts/metrics-append-item.sh <story-id> [<size_est> [<ep_est> [<loc> [<files> [<blocked> [<lang> [<cost_mode> [<tok_est>]]]]]]]]` (Rollup aus den Dispatches). Append-only, idempotenz-tolerant, `|| true`.
- **Ledger-Schema** unverändert (`docs/architecture/metrics-subsystem.md §2`) — einzige Änderung: `item` als `S-###`-String.
- **Aufrufer:** `skills/flow/SKILL.md §2b` ruft die Skripte an den bestehenden Touchpoints (Dispatch / Done) auf; `metrics-collect.sh` unverändert in der Aufruf-Kette (V3 fixt nur die Pfad-Auflösung).

## Edge-Cases & Fehlerverhalten

- **Append-Skript schlägt fehl** → still (`|| true`), Loop läuft; V4-Self-Check meldet die fehlende Zeile.
- **Transcripts nicht auffindbar** → `tok` bleibt null, kein Crash; V4 meldet leeres Token.
- **Alt-Story mit int-`item`** → bleibt, wird nicht migriert (AC7); dev-gui matcht tolerant.
- **Story-Anlauf ohne Done** (Blocked/Abbruch) → Dispatch-Zeilen vorhanden, keine items-Zeile (erwartet).

## NFRs

- **Kein Loop-Risiko:** Messen bleibt K3 (still) + K4 (gate-neutral); nur die Sichtbarkeit (V4) ist additiv.
- **~0 LLM-Token:** reine Bash/jq-Arithmetik (K1).

## Nicht-Ziele

- **Rückbefüllung historischer Stories** (S-165 & Co.) — nicht rekonstruierbar.
- **Neues Ledger-Format/Speicher** — nur `item`-String + zuverlässige Auslösung.
- **GUI-Anzeige** — separat ([[../specs/story-detail-yaml-fallback]] in dev-gui).

## Abhängigkeiten

- **agent-flow:** `skills/flow/SKILL.md §2b`, `scripts/metrics-collect.sh`, neue `scripts/metrics-append-*.sh`, `docs/architecture/metrics-subsystem.md`, [[metrics-token-collect]].
- **Cross-Repo (Konsument):** dev-gui `story-detail-yaml-fallback` — zeigt die erfassten Daten + toleriert Alt-int-IDs.
