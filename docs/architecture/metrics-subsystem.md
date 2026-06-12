# Architecture — Metrik-/Performance-Subsystem (Effort-Points, Soll-Ist, Retro-Effektivität)

> **Bindend.** Diese Spec beschreibt **wie** das `agent-flow`-Plugin Leistung/Aufwand der Agenten **messbar** macht — pro Agent-Dispatch und pro Board-Item — um künftig Aufwand/Komplexität vorherzusagen, **Soll gegen Ist** abzurechnen und die **Effektivität von `retro`/`train`** quantitativ zu belegen. Sie ist die Ausgestaltung von **CONCEPT §5a „Tier 2"**. Tragendes Designprinzip: **minimale Token-Kosten** — Messen läuft als deterministische Arithmetik im ohnehin laufenden `/flow`-Orchestrator (kein zweiter LLM-Lauf). Abweichungen sind Review-Kriterium.

---

## 1. Zweck & Scope

**Zweck.** CONCEPT §5a hält für „Tier 2 (später)" fest: *„`/flow` loggt pro Item Metriken (Iterationen-bis-PASS, #Critical/Important, Test-First-Pass, Blocked) → Trends + GitHub Projects Insights-Charts."* Dieses Subsystem **ist** Tier 2 — und geht darüber hinaus:

- **Aufwand messbar machen** — eine synthetische, kalibrierbare Aufwands-Münze (**Effort Points, EP**) je Item, billig im Alltag berechnet, später gegen echte Token/Zeit geeicht.
- **Vorhersagen** — beim Item-Eintritt eine A-priori-Grössenklasse (S/M/L/XL) heuristisch ableiten und daraus erwarteten Aufwand (`ep_est`) prognostizieren.
- **Soll gegen Ist** — `ep_est` neben `ep_act` in dieselbe Ledger-Zeile; der **Forecast-Fehler** wird selbst zur Systemmetrik (Prognosegüte, soll mit Datenmenge sinken).
- **Retro-Effektivität quantifizieren** — weil `reviewer` jeden Befund mit Regel-ID taggt (CONCEPT §5a) und diese `rule_hits` nun im Ledger landen, wird die **Defektrate je Regel-ID** (Treffer pro 100 EP) über die Zeit gratis auswertbar → `LEARNINGS.md`-Status `Measuring → Validated | Reverted` wird **quantitativ** statt nach Bauchgefühl.

**Motivation (begründet).**

- **Nullkosten durch Wiederverwendung.** `/flow` ist einziger Orchestrator + einziger Board-Schreiber und liest die Handoff-Marker (`Review-Handoff … (Iteration N)`, `Review-Gate: PASS|CHANGES-REQUIRED` + `## Critical/## Important`, `Test-Gate: PASS|FAIL`, `Rollout-Gate`) **ohnehin im Klartext**. Diese Signale zusätzlich zu ZÄHLEN und als strukturierte Zeile wegzuschreiben kostet ~0 zusätzliche LLM-Tokens — es ist deterministische Arithmetik, kein zweiter LLM-Lauf.
- **Single-Writer.** Genau **ein** Schreiber (`/flow`), append-only — keine Race-Conditions, kein Doppel-Logging, kein Agent schreibt Prosa-Reports.
- **Ehrliche Token-Erfassung out-of-band.** Echte Token werden NICHT beim Agenten erfragt (unzuverlässig + kostet selbst Tokens), sondern nach Item-Abschluss aus den Subagent-Transcript-Dateien geparst (0 LLM-Tokens). EP funktioniert auch ohne Token — Token sind die spätere **Eich-Datenquelle**, kein Pflicht-Input.
- **Proxy jetzt, real nachgezogen.** EP ist im Alltag eine billige feste Arithmetik; `retro` eicht die Gewichte periodisch gegen die echten `tok_total`/`secs_total`. So bleibt das tägliche Messen quasi gratis und wird trotzdem real kalibriert.

**Out of Scope.**

- **Kein zweiter LLM-Lauf zur Messung.** Das Erfassen selbst ist deterministisch (Marker zählen, `git diff --shortstat`, `date`/jq). LLM-Aufwand fällt NUR an für die optionale 1-Satz-Schätzkorrektur bei L/XL (§7) und die periodische `retro`-Aggregation (§8) — beides selten/bewusst.
- **Kein Echtzeit-Dashboard.** Auswertung läuft über die JSONL-Ledger + die periodische `baseline.json`-Aggregation + GitHub-Projects-Insights. Kein eigener Render-/Server-Pfad.
- **Keine Pro-Token-Dollar-Optimierung.** Der Betrieb läuft unterm Abo (kein Dollar-API-Kostenmodell, vgl. model-tier-subsystem §1). EP/Token messen **Aufwand/Kontingent-Verbrauch**, sind kein Dollar-Optimierer.
- **Kein Agent verändert das Ledger.** `coder`/`reviewer`/`tester`/`dba`/`cicd` schreiben weder JSONL noch `baseline.json`. Erfassung = `/flow`; Aggregation = `retro`.

---

## 2. Datenmodell (zwei JSONL-Ledger + ein Baseline-Aggregat)

Drei Dateien pro Projekt unter `.claude/metrics/` (append-only Ledger + ein vom `retro` neu geschriebenes Aggregat). Alle gitignored bis auf bewusste Snapshots — siehe §11.

### 2.1 `.claude/metrics/dispatches.jsonl` — eine Zeile JE AGENT-DISPATCH

Pro-Dispatch-Granularität (explizit gewünscht): jeder einzelne Task-Dispatch eines Agenten erzeugt **eine** Zeile. Felder:

| Feld | Typ | Bedeutung |
|---|---|---|
| `ts` | string (ISO-8601 UTC) | Dispatch-Ende-Zeitstempel |
| `item` | int | Board-Item-/Issue-Nummer |
| `seq` | int | laufende Dispatch-Nummer **innerhalb** des Items (1, 2, 3 …) |
| `agent` | string | `coder` \| `reviewer` \| `dba` \| `tester` \| `cicd` |
| `iter` | int | Build-Loop-Iteration (aus `Review-Handoff … (Iteration N)`); für nicht-Loop-Rollen die zugehörige Iteration |
| `gate` | string \| null | `PASS` \| `CHANGES-REQUIRED` \| `FAIL` \| `SKIPPED-*` \| `null` (rollen-abhängig: Review-Gate / Test-Gate / Rollout-Gate) |
| `crit` | int | #Critical-Befunde dieses Dispatches (nur reviewer/dba; sonst 0) |
| `imp` | int | #Important-Befunde dieses Dispatches (nur reviewer/dba; sonst 0) |
| `rule_hits` | string[] | die Regel-ID-Tags, die der reviewer/dba diesem Dispatch vergeben hat (z.B. `["coder/R01","sql/R03"]`); leer = `[]` |
| `secs` | int \| null | Wall-Clock-Dauer des Dispatches in Sekunden (`date -u +%s`-Klammer) |
| `tok` | object \| null | `{ "in": int, "out": int, "cache": int }` — echte Token (best-effort, out-of-band; §6). Nicht parsebar → `null` |
| `cost_mode` | string | aktiver Cost-Mode des Laufs (`low-cost` \| `balanced` \| `max-quality` \| `frontier`) |

### 2.2 `.claude/metrics/items.jsonl` — eine Zeile JE BOARD-ITEM beim Done (Rollup)

Genau **eine** Zeile, geschrieben wenn `/flow` das Item auf `Done` setzt (Rollup aller Dispatches des Items). Felder:

| Feld | Typ | Bedeutung |
|---|---|---|
| `ts` | string (ISO-8601 UTC) | Done-Zeitstempel |
| `item` | int | Board-Item-/Issue-Nummer |
| `size_est` | string | A-priori-Grössenklasse `S` \| `M` \| `L` \| `XL` (§7) |
| `ep_est` | number \| null | prognostizierter Aufwand (aus `baseline.json`-Mapping; `null` solange keine Baseline existiert) |
| `ep_act` | number | tatsächlicher Aufwand nach EP-Formel (§5) |
| `iters` | int | Build-Loop-Iterationen bis PASS (max. der `iter`-Werte) |
| `crit` | int | Σ Critical über alle Dispatches des Items |
| `imp` | int | Σ Important über alle Dispatches des Items |
| `test_fails` | int | #`Test-Gate: FAIL` über alle Dispatches des Items |
| `rule_hits` | string[] | Vereinigung aller `rule_hits` des Items (für §9-Defektraten) |
| `loc` | int | geänderte Lines-of-Code (`git diff --shortstat`: insertions+deletions) |
| `files` | int | geänderte Dateien (`git diff --shortstat`) |
| `tok_total` | int \| null | Σ echte Token über alle Dispatches; `null` wenn keine Token parsebar |
| `secs_total` | int \| null | Σ Wall-Clock über alle Dispatches |
| `blocked` | int | 1 wenn das Item zwischenzeitlich blockiert war (NEEDS-HUMAN / depends ungelöst / manueller Eingriff), sonst 0 |
| `lang` | string | `profile.lang` (für Baseline-Schnitt) |
| `cost_mode` | string | aktiver Cost-Mode des Laufs |

### 2.3 `.claude/metrics/baseline.json` — Aggregat (von `retro` geschrieben)

Mediane je **Grösse × Sprache × cost_mode** plus die kalibrierten EP-Gewichte. Struktur (illustrativ, bindend ist die Schlüssel-Semantik):

```json
{
  "calibrated_at": "2026-06-12",
  "n_items": 137,
  "ep_per_token": 0.0021,
  "weights": { "iter": 2, "crit": 1, "imp": 0.5, "test_fail": 2, "loc_log": 1, "blocked": 3 },
  "medians": {
    "md|balanced|S": { "ep": 3.0, "iters": 1, "crit": 0, "tok_total": 1400, "secs_total": 95 },
    "md|balanced|M": { "ep": 7.5, "iters": 2, "crit": 1, "tok_total": 5200, "secs_total": 310 }
  },
  "forecast_mae": 0.34
}
```

- `medians`-Schlüssel = `<lang>|<cost_mode>|<size>`. Fehlt ein Schnitt → §7-Fallback (nächstgröbere Aggregation, zuletzt globaler Median).
- `ep_per_token` = das Eich-Ergebnis (1 EP ≈ X echte Token, §8).
- `forecast_mae` = mittlerer absoluter Forecast-Fehler `|ep_est − ep_act| / ep_act` über die Historie (Prognosegüte-Tracker).

---

## 3. Effort Points (EP) — die Aufwands-Münze

Fixe Arithmetik in `/flow`, deterministisch aus den ohnehin gezählten Markern:

```
EP = 1
   + 2 · (iters − 1)        # jede zusätzliche Build-Loop-Iteration
   + 1 · crit               # je Critical-Befund
   + 0.5 · imp              # je Important-Befund
   + 2 · test_fails         # je Test-Gate: FAIL
   + round(log10(loc + 1))  # Grössen-Dämpfung der Diff-Grösse
   + 3 · blocked            # Blockade-Strafe (0/1)
```

- **Startgewichte** (oben). Sie sind die initiale Schätzung und werden später durch `retro` gegen echte Token/Zeit **kalibriert** (§8) — die kalibrierten Gewichte leben in `baseline.json.weights` und haben Vorrang vor diesen Defaults, sobald vorhanden.
- `loc` = `insertions + deletions` aus `git diff --shortstat` des Item-Diffs (gegen den `default_branch`-Stand bei Item-Eintritt).
- EP ist **token-frei** berechenbar — `tok` ist NICHT Teil der Formel, nur Eich-Datenquelle. Ein Item ohne parsebare Token hat trotzdem ein valides `ep_act`.

---

## 4. Erfassungs-Touchpoints in `/flow` (deterministisch, ~0 Token)

`/flow` ist einziger Metrik-Schreiber. Touchpoints im bestehenden Loop (`coder → reviewer ⇄ tester → cicd ship → Done`):

1. **Vor jedem Task-Dispatch** (coder/reviewer/dba/tester/cicd): `T0=$(date -u +%s)` merken.
2. **Nach jedem Dispatch**: aus dem Klartext-Handoff zählen — `gate` (das jeweilige `*-Gate`), `iter` (aus `Review-Handoff … (Iteration N)`), `crit`/`imp` (Anzahl Einträge unter `## Critical` / `## Important`), `rule_hits` (die Regel-ID-Tags der Befunde). `secs = $(date -u +%s) − T0`. **Eine Zeile** nach `dispatches.jsonl` appenden (`tok` zunächst `null`, wird in Schritt 4 best-effort nachgetragen).
3. **Beim Done** (Item → `Done`, nach Rollout-Gate PASS): `git diff --shortstat` für `loc`/`files`; Dispatches des Items rollupen (`iters`, Σ`crit`, Σ`imp`, `test_fails`, `rule_hits`-Union, `secs_total`); `ep_act` nach §3; `ep_est` aus dem beim Eintritt bestimmten `size_est` × `baseline.json` (§7). **Eine Zeile** nach `items.jsonl`.
4. **Token-Nachtrag (out-of-band, §6)**: nach dem Item-Abschluss `scripts/metrics-collect.sh <item>` aufrufen → parst die Subagent-Transcripts, summiert `tok` je Dispatch, patcht die `tok`-Felder der betroffenen `dispatches.jsonl`-Zeilen + `tok_total` der `items.jsonl`-Zeile. Schlägt das fehl (Pfad/Format unbekannt) → Felder bleiben `null`, kein Abbruch.

**Schreib-Disziplin:** append-only; bei (4) ein In-Place-Patch derselben Zeilen über das Script (jq-Rewrite), KEIN zweiter LLM-Lauf. Fehlerhafte/unvollständige Marker → das betroffene Feld `null`/`0`, nie raten, nie das Item blockieren (Messen darf den Loop nie aufhalten — Best-Effort-Prinzip).

---

## 5. Token/Zeit out-of-band (best-effort) + Phase-0-Caveat

- **Wall-Clock** (`secs`): trivial über die `date -u +%s`-Klammer um jeden Dispatch (§4.1/4.2). Immer verfügbar.
- **Echte Token** (`tok`): ein Bash/jq-Script `scripts/metrics-collect.sh` parst NACH Item-Abschluss die **Subagent-Transcript-JSONL** (`agent-<id>.jsonl` im Session-Transcript-Verzeichnis; enthalten `usage`-Felder `input_tokens`/`output_tokens`/`cache_*`) und summiert Token je Dispatch → **0 LLM-Tokens**.
- **EHRLICHE Annahme (das einzige unsichere Stück):** Pfad **und** Format dieser Transcript-Dateien sind nicht garantiert. Darum verlangt die zugehörige Spec eine **Phase-0-Verifikation** des tatsächlichen Pfads/Formats *bevor* der Token-Pfad als verlässlich gilt. Ist nichts Parsebares auffindbar → `tok`/`tok_total` fallen sauber auf `null` zurück; EP + alle übrigen Metriken funktionieren ungestört weiter. Der Token-Pfad ist additiv, nie eine Vorbedingung.

---

## 6. A-priori-Schätzung + Soll-Ist-Abrechnung

- **Grössenklasse (rein heuristisch, token-frei):** beim Item-Eintritt leitet `/flow` `S` \| `M` \| `L` \| `XL` ab aus (a) #Acceptance-Kriterien der referenzierten Spec, (b) Labels (`db`, `security`, `ui` gewichten hoch), (c) #genannter Komponenten/Dateien im Item-Body. Schwellen sind in der Capability-Spec als AC fixiert.
- **LLM-Schätzer NUR bei L/XL** (token-sparsam, bewusst entschieden): für gross eingestufte Items eine **1-Satz**-Korrektur (Plausibilitäts-Check der Heuristik). S/M laufen rein heuristisch, kein LLM.
- **Mapping est→EP:** `size_est` mappt über `baseline.json.medians[<lang>|<cost_mode>|<size>]` auf `ep_est` (+ erwartete `iters`/`crit`). Fehlt der Schnitt → gröbere Aggregation, zuletzt globaler Median; existiert noch GAR keine Baseline → `ep_est = null` (das ist der erwartete Zustand bis Phase 1 genug Historie hat).
- **Soll-Ist:** beim Done landet `ep_est` neben `ep_act` in derselben `items.jsonl`-Zeile. Der **Forecast-Fehler** `|ep_est − ep_act| / ep_act` ist eine eigene Systemmetrik (Prognosegüte; `baseline.json.forecast_mae` trackt den gleitenden Mittelwert — soll mit Datenmenge sinken).

---

## 7. `retro`: Aggregation + EP-Kalibrierung

`retro` läuft ohnehin selten (~1×/Woche, Cooldown-Gitter G3) — der richtige Ort für die teurere Analyse **auf Zahlen statt Code**. Zusätzlich zum Lessons-Destillieren (Modus A) bekommt `retro` eine **Mess-Aufgabe**:

- **Aggregation:** periodisch die beiden Ledger einlesen → `baseline.json` neu schreiben: Mediane je `<lang>|<cost_mode>|<size>` (EP, iters, crit, tok_total, secs_total).
- **EP-Kalibrierung:** die EP-Gewichte werden gegen die echten `tok_total`/`secs_total` per **linearer Regression** geeicht (`ep_per_token` = 1 EP ≈ X echte Token; ggf. einzelne `weights` nachjustiert). Damit ist EP eine **kalibrierte Proxy-Münze**: billig im Alltag, real nachgezogen. Die kalibrierten `weights` haben in `/flow` Vorrang vor den §3-Defaults.
- **Schutzgitter respektieren:** Cooldown (G3, 1×/Woche/Repo via `.retro-last-run`), PR+Gate-Mechanik. Die Mess-Aggregation ist ein **deterministischer Rechenschritt** im retro-Lauf (kein zusätzlicher LLM-Reasoning-Block über §8 hinaus). Schreibt `baseline.json` als Teil des regulären retro-Outputs.

---

## 8. Retro-Effektivität messen (der Clou)

Weil `reviewer`/`dba` jeden Befund mit Regel-ID taggen (CONCEPT §5a) und diese `rule_hits` jetzt im Ledger landen, ist die **Defektrate je Regel-ID** = *Treffer pro 100 EP* über die Zeit gratis auswertbar:

- **Quantitativer LEARNINGS-Lebenszyklus:** beim Promoten einer Regel (`Measuring`) hält man die **Baseline-Defektrate** der adressierten Regel-ID fest. Nach **N** weiteren Items misst man die neue Rate:
  - signifikant gesunken → `Validated` (mit Zahl, z.B. „`coder/R01`: 4.2 → 0.8 Treffer/100 EP über 30 Items").
  - kein Effekt/schlechter → `Reverted` (`git revert`, Zahl als Begründung).
- **Retro-Effektivität gesamt** = aggregierte EP-/Defekt-Reduktion über alle `Validated` minus dem Schaden der `Reverted`. Das macht CONCEPT §5a „Maßstab: kehrt der Fehler weiter wieder?" von qualitativ zu **quantitativ**.

Diese Auswertung ist Teil des `retro`-Mess-Schritts (§7) — selten, auf Zahlen, kein Pro-Item-Aufwand.

---

## 9. CONCEPT-Anschluss (§5a → Tier 2)

CONCEPT §5a endet mit *„Tier 2 (später): `/flow` loggt pro Item Metriken … → Trends + GitHub Projects Insights-Charts."* Dieses Subsystem **ist** die Ausgestaltung von Tier 2 + Vorhersage + Eichung + Retro-Effektivität. Der §5a-Absatz wird so fortgeschrieben, dass er auf **diese** Architektur-Spec verlinkt (die Source of Truth für Tier 2). Kein Verhaltens-Bruch zu Tier 1 — Tier 1 (LEARNINGS-Ledger, Regel-ID-Tagging) bleibt unverändert und ist die **Eingangs-Datenquelle** für §8.

---

## 10. Schutz- & Kosten-Prinzipien (bindende Invarianten)

- **K1 — Messen kostet ~0 LLM-Token.** Erfassung (§4) ist deterministische Arithmetik + Bash/jq. LLM-Aufwand fällt NUR bei der L/XL-1-Satz-Schätzung (§6) und im periodischen `retro` (§7/§8) an.
- **K2 — Single-Writer.** Nur `/flow` schreibt die Ledger (append-only); nur `retro` schreibt `baseline.json`. Kein anderer Agent berührt `.claude/metrics/`.
- **K3 — Messen blockiert nie den Loop.** Jeder fehlende/unparsebare Wert fällt auf `null`/`0`; kein Metrik-Fehler darf ein Item aufhalten oder ein Gate verändern.
- **K4 — Token sind additiv, nie Vorbedingung.** EP + alle Item-Metriken funktionieren ohne `tok`. Der Transcript-Pfad ist best-effort (§5).
- **K5 — Append-only + auditierbar.** Ledger werden nur angehängt (Token-Nachtrag patcht nur `null`-Felder derselben Zeilen). Keine Löschung, keine Umschreibung historischer Aufwands-Werte.
- **K6 — Keine Secrets im Ledger.** Nur Zähl-/Aufwands-Metriken, nie Diff-Inhalte, nie Befund-Prosa, nie Credentials.

---

## 11. Datei-Hygiene

- `.claude/metrics/dispatches.jsonl` + `items.jsonl` sind **lokale Mess-Ledger** (gitignored per Default — sie wachsen pro Lauf und sind maschinen-lokal). `baseline.json` ist das **bewusst committete** Aggregat (klein, reviewbar, von `retro` per PR/Commit gepflegt — analog `LEARNINGS.md`).
- `scripts/metrics-collect.sh` ist ein reguläres committetes Plugin-Script (wie die übrigen `scripts/*.sh`).

---

## 12. Rollout-Wellen (→ depends-Kette der Board-Items)

Ohne Historie ist nichts schätzbar → **Phase 0 zuerst**:

| Phase | Inhalt | Capabilities (Specs) |
|---|---|---|
| **0 — Fundament** | Schema + Erfassung in `/flow` + Wall-Clock + EP-Formel; Token-Out-of-band-Script + Phase-0-Verifikation | `metrics-ledger`, `metrics-token-collect` |
| **1 — Aggregation/Eichung** | `retro`-Aggregation → `baseline.json`; EP-Kalibrierung; Soll-Ist-Spalten | `metrics-retro-aggregation` |
| **2 — Schätzung/Forecast** | A-priori-Grössenklasse + `ep_est` + Forecast-Fehler | `metrics-estimation` |
| **3 — Retro-Effektivität** | Defektrate je Regel-ID; LEARNINGS `Measuring → Validated\|Reverted` quantitativ | `metrics-retro-effectiveness` |
| **CONCEPT-Anschluss** | §5a fortschreiben + auf diese Spec verlinken | gebündelt mit Phase 0 (`metrics-ledger`) |

---

## 13. Verifikation / Review-Kriterien

- K1–K6 prüfbar: kein Erfassungs-Pfad löst einen zweiten LLM-Lauf aus; nur `/flow` schreibt Ledger; ein fehlender Marker → `null`/`0`, nie Loop-Abbruch.
- EP-Formel (§3) bitgenau wie spezifiziert; kalibrierte `weights` aus `baseline.json` haben Vorrang, sobald vorhanden.
- Token-Pfad (§5): Phase-0-Verifikation belegt Pfad/Format ODER `tok` fällt dokumentiert auf `null`.
- Datei-Hygiene (§11): Ledger gitignored, `baseline.json` committet.
- Drift-Gate: Änderungen an Feldsemantik/EP-Formel gehören in **diese** Spec, nicht verstreut in Skill-/Agent-Defs.
