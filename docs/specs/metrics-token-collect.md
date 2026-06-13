---
id: metrics-token-collect
title: Token/Zeit out-of-band erfassen (best-effort, Eich-Datenquelle)
status: approved
version: 1
---

# Spec: Token-Erfassung out-of-band  (`metrics-token-collect`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Subsystem ist in `docs/architecture/metrics-subsystem.md` spezifiziert (bindend, §5). Diese Spec beschreibt die **Phase-0-Capability** zur Befüllung der `tok`-Felder: ein Bash/jq-Script, das echte Token aus den Subagent-Transcript-Dateien parst — **0 LLM-Token**. Sie baut auf dem Ledger-Schema aus `metrics-ledger` auf.

## Zweck

Echte Token sind die spätere **Eich-Datenquelle** für die EP-Kalibrierung. Sie werden NICHT beim Agenten erfragt (unzuverlässig + kostet selbst Token), sondern nach Item-Abschluss aus den Subagent-Transcript-JSONL geparst und je Dispatch summiert — ein deterministisches Bash/jq-Script (`scripts/metrics-collect.sh`), das die zuvor von `/flow` als `null` geschriebenen `tok`-Felder patcht.

## Kontext / Designnuancen (bindend)

- **EHRLICHE Annahme — das einzige unsichere Stück.** Pfad UND Format der Transcript-Dateien (`agent-<id>.jsonl` im Session-Transcript-Verzeichnis, mit `usage`-Feldern) sind nicht garantiert. Diese Capability MUSS deshalb mit einer **Phase-0-Verifikation** beginnen, die den tatsächlichen Pfad/das Format belegt, bevor der Token-Pfad als verlässlich gilt.
- **Sauberer Fallback.** Ist nichts Parsebares auffindbar → `tok`/`tok_total` bleiben `null`. EP + alle übrigen Metriken funktionieren ungestört weiter (subsystem §10 K4). Der Token-Pfad ist additiv, nie Vorbedingung.
- **0 LLM-Token.** Reines Bash/jq nach Item-Abschluss; kein Agent-Dispatch, kein Reasoning-Block.
- **Append-only-konform.** Das Script patcht ausschliesslich `null`-`tok`-Felder bestehender Zeilen (jq-Rewrite derselben Zeilen), keine Neu-Zeilen, keine Wert-Überschreibung historischer Aufwands-Felder (subsystem §10 K5).

## Verhalten

### V1 — Phase-0-Verifikation (Pflicht-Vorbedingung)
Vor produktivem Einsatz wird der **tatsächliche** Transcript-Pfad + das `usage`-Feldformat empirisch verifiziert (ein realer Dispatch, Pfad gelistet, `usage`-Keys belegt: `input_tokens`/`output_tokens`/`cache_*` o.Ä.). Das Ergebnis (verifizierter Pfad/Format ODER „nicht parsebar → Fallback") wird in der Spec/im Script-Header dokumentiert. Ist nichts verifizierbar → das Script ist ein No-Op, der `tok` sauber auf `null` lässt.

**Phase-0-Ergebnis (verifiziert 2026-06-12, Item #109):**

Transcript-Dateien wurden unter `~/.claude/projects/<escaped-cwd>/<session-uuid>/subagents/` gefunden. Escaping: cwd-Pfad mit `/` → `-` (z.B. `/Users/alex/Git/Studis-Softwareschmiede` → `-Users-alex-Git-Studis-Softwareschmiede`). Jede Subagent-Dispatch hat zwei Dateien: `agent-<id>.jsonl` (Conversation-Log) und `agent-<id>.meta.json` (Metadaten mit `agentType` und `description`). Die `description` im meta.json enthält beim Dispatch durch `/flow` zuverlässig `#<item>` (z.B. `"coder #108 Ledger-Schema"`), was die Item-Zuordnung ermöglicht.

Format der `usage`-Felder in assistant-Zeilen des JSONL (alle Keys konsistent über alle geprüften Subagents):
```json
{
  "input_tokens": <int>,
  "output_tokens": <int>,
  "cache_creation_input_tokens": <int>,
  "cache_read_input_tokens": <int>,
  "server_tool_use": { ... },
  "service_tier": "standard",
  "cache_creation": { ... },
  "inference_geo": "not_available",
  "iterations": [ ... ],
  "speed": "standard"
}
```
Summierung je Subagent: `in = Σ input_tokens`, `out = Σ output_tokens`, `cache = Σ (cache_creation_input_tokens + cache_read_input_tokens)` über alle assistant-Zeilen.

**Einschränkung:** Der Transcript-Pfad hängt vom cwd der Eltern-Session ab, nicht vom cwd des Subagents. Das Script durchsucht deshalb alle Projekt-Verzeichnisse nach `#<item>` in der `description`. Für Items, die nicht von `/flow` dispatcht wurden (fehlende `#N`-Konvention in der description), findet das Script keine Transcripts und fällt auf `null` zurück — das ist korrekt und erwartet.

### V2 — Script `scripts/metrics-collect.sh`
Ein committetes Bash/jq-Script `scripts/metrics-collect.sh <item>`: parst die Subagent-Transcript-JSONL des Items, summiert `input`/`output`/`cache`-Token je Dispatch, und ordnet sie den Dispatch-Zeilen des Items zu (über die Dispatch-/Zeit-Korrelation, die `/flow` kennt).

### V3 — In-Place-Patch der `null`-Felder
Das Script patcht die `tok`-Felder der betroffenen `dispatches.jsonl`-Zeilen (`{in,out,cache}`) und das `tok_total` der `items.jsonl`-Zeile des Items. Es überschreibt **nur** `null`-Werte; bereits gesetzte Token-/Aufwands-Werte bleibt unverändert (append-only-Geist, K5).

### V4 — /flow-Aufruf nach Item-Abschluss
`/flow` ruft `scripts/metrics-collect.sh <item>` nach dem Item-Done auf (subsystem §4 Schritt 4). Schlägt das Script fehl oder findet nichts → `tok`/`tok_total` bleiben `null`, **kein Abbruch**, das Item bleibt `Done`.

### V5 — Best-effort + Fehlertoleranz
Jeder Fehler im Token-Pfad (Pfad fehlt, Format unerwartet, jq-Fehler) führt zu `null`, nie zu einem Loop-Stopp, nie zu einer Gate-Änderung (subsystem §10 K3/K4). Das Script gibt einen einzeiligen Hinweis aus, wenn der Token-Pfad nicht verfügbar war.

### V6 — Keine Token-Erfragung beim Agenten
Weder `/flow` noch das Script fragen einen Agenten nach seinem Token-Verbrauch. Token kommen ausschliesslich aus den Transcript-Dateien (0 LLM-Token).

## Acceptance-Kriterien

- **AC1** — Eine Phase-0-Verifikation belegt den tatsächlichen Transcript-Pfad + das `usage`-Feldformat (oder dokumentiert „nicht parsebar → Fallback"); das Ergebnis ist im Script-Header/der Spec festgehalten. *(V1)*
- **AC2** — `scripts/metrics-collect.sh <item>` existiert als committetes Bash/jq-Script und summiert Token (`in`/`out`/`cache`) je Dispatch aus den Subagent-Transcripts. *(V2)*
- **AC3** — Das Script patcht ausschliesslich `null`-`tok`-Felder der betroffenen `dispatches.jsonl`-Zeilen + `tok_total` der `items.jsonl`-Zeile; bestehende Werte bleiben unverändert; keine neuen Zeilen. *(V3, K5)*
- **AC4** — `/flow` ruft das Script nach Item-Done auf; ein Fehlschlag lässt `tok`/`tok_total` auf `null`, ohne Abbruch und ohne das Item aus `Done` zu nehmen. *(V4)*
- **AC5** — Jeder Token-Pfad-Fehler resultiert in `null` (nie Loop-Stopp, nie Gate-Änderung); ein einzeiliger Hinweis wird ausgegeben. *(V5, K3/K4)*
- **AC6** — Token werden niemals beim Agenten erfragt; kein Dispatch/LLM-Lauf entsteht für die Token-Erfassung (0 LLM-Token). *(V6)*

## Nicht-Ziele

- EP-Formel/Ledger-Schema (`metrics-ledger`).
- EP-Kalibrierung gegen Token (`metrics-retro-aggregation`).
- A-priori-Schätzung (`metrics-estimation`).
