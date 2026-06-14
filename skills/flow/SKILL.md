---
name: flow
description: Orchestriert die Softwareschmiede — liest das Projekt-Board und arbeitet die To-Do-Items Punkt für Punkt ab (coder → reviewer ⇄ Loop → tester → cicd ship → Done). Einziger Schreiber von Board-Status. Git-Abschluss-Operationen (merge+push) delegiert /flow an cicd als ausführenden Abschluss-Arm. Im Ziel-Projekt-Repo ausführen.
---

# /flow [--cost <mode>] — Board abarbeiten (Orchestrator)

Du bist der **Orchestrator** (Haupt-Session). Du dispatchst die Agenten via Task-Tool und bist der **einzige Schreiber** von Board-Status. Git/PR-Operationen im Abschluss werden an `cicd` als ausführenden Arm delegiert (s. §5). cwd = Ziel-Projekt-Repo.

**Cost-Mode (Token-Hebel).** Jeder Agent-Dispatch dieses Laufs erhält einen **`model`-Override** gemäß dem aktiven Cost-Modus (in §0 aufgelöst). Aufruf optional mit `--cost <low-cost|balanced|max-quality|frontier>` (Kurz: `low`/`max`/`front`; `frontier` = opt-in, nie Default). Im Modus `balanced` wird **kein** Override gesetzt (Agent-Frontmatter gilt). Matrix + Auflösungsregeln: `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md`.

## 0. Setup
- `.claude/profile.md` lesen → Board-Referenz, `merge_policy` (`pr`|`direct`), Build/Test-Befehle, **`default_branch`**, **`cost_mode`** (Default `balanced`).
- **Cost-Mode auflösen** (einmal, merken — gilt für ALLE Dispatches dieses Laufs): Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced`. Kurzformen normalisieren (`low`→`low-cost`, `max`/`high`→`max-quality`, `front`→`frontier`). Unbekannter Wert → `balanced` + einzeiliger Hinweis (**nie** auf `frontier` raten — opt-in). **Beim Task-Dispatch jedes Agenten** (coder/reviewer/dba/tester in §3–§4 sowie **cicd** beim SHIP-Dispatch in §5) den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Zeile = Rolle, Spalte = Modus) mitgeben; bei `balanced` **keinen** `model`-Parameter setzen (Frontmatter gilt). Einmal zu Beginn ausgeben: „⚙ Cost-Mode: <mode>".
- **Arbeits-Repo Fork-sicher auflösen** (einmal, merken): Das Arbeits-Repo ist **`origin`**. ⚠️ `gh repo view` **ohne Argument** liefert bei einem Fork das **Upstream-Parent** (gh bevorzugt den `upstream`-Remote) — deshalb IMMER die origin-URL explizit übergeben:
  - `repo="$(gh repo view "$(git remote get-url origin)" --json nameWithOwner -q .nameWithOwner)"`
  - Fehlt `profile.default_branch` (Alt-Repo): `default_branch="$(gh repo view "$(git remote get-url origin)" --json defaultBranchRef -q .defaultBranchRef.name)"` (NICHT `main` annehmen — adoptierte Forks haben oft `master`).
- **Auth herstellen:** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token aus `.env.gpg`, loggt `gh` ein). **NICHT `gh auth login --web`.**
- **Security-Frische (einmaliger Nudge):** `last_trained:` aus `${CLAUDE_PLUGIN_ROOT}/knowledge/security.md` lesen; ist es **> 90 Tage** her → einmal ausgeben: „🔒 security-Pack ist <N> Tage alt — `/train security` erwägen." (nur Hinweis, blockiert nicht).

## 1. Nächstes Item wählen
- `board next` → die nächste bereite Story als JSON (`id`, `spec`, `implements`, `parent`, `labels`, `priority`); Queue-Logik (Priority, Depends-Gate) lebt in der CLI.
- Aus dem JSON die **Spec-Referenz** lesen: `spec: docs/specs/<feature>.md` + `implements: [AC…]` — die reichst du an coder/reviewer/tester durch (Source of Truth, nicht der Story-Titel).
- Leere Ausgabe → nichts zu tun; weiter zu **7. Abschluss-Deploy** (statt sofort stoppen).

### 1a. A-priori-Grössenklasse + `ep_est` (Spec `metrics-estimation` AC1–AC3, §2b)

> **Einziger Schreiber:** Schätzung + Mapping laufen hier in /flow; das Ergebnis (`size_est`, `ep_est`) wird beim Done in `items.jsonl` eingetragen. **Kein LLM-Aufruf für S/M.** Fehler → `size_est = "M"`, `ep_est = null`, kein Loop-Abbruch (K3).

**Schritt A — Heuristik (token-frei, deterministisch):**

Zähle aus Item-Body + referenzierter Spec (`docs/specs/<feature>.md`):
- `n_ac` = #Acceptance-Kriterien (Zeilen die mit `- **AC` beginnen oder AC-Nummerierung tragen)
- `n_comp` = #genannter Komponenten/Dateien (grobe Zählung: Pfade, Agenten, Scripts im Item-Body)
- `label_bump` = +1 für jedes der Labels `db`, `security`, `ui` am Board-Item (max +3)

**Roher Score:** `score = n_ac + n_comp + label_bump`

**Mapping Score → Grössenklasse** (Schwellen fixiert, Spec `metrics-estimation` AC1):

| Score | `size_est` |
|---|---|
| 0–3   | `S` |
| 4–7   | `M` |
| 8–12  | `L` |
| ≥ 13  | `XL` |

**Schritt B — LLM-Korrektur nur bei L/XL (AC2):**

Wurde `size_est` als `L` oder `XL` eingestuft: formuliere **1 Satz** (token-sparsam): „Ist diese Schätzung plausibel oder soll ich auf [kleinere/grössere Klasse] anpassen?" und beantworte die Frage im selben Reasoning-Schritt anhand des tatsächlichen Item-Umfangs. Korrigiere `size_est` falls offensichtlich falsch — keine eigene LLM-Runde, integriert in den laufenden Reasoning-Kontext. **S/M laufen ohne diese Korrektur.**

**Schritt C — Mapping size_est → ep_est (AC3):**

Lese `.claude/metrics/baseline.json` (falls vorhanden). Lookup-Reihenfolge:

1. Exakter Schnitt: `medians["<lang>|<cost_mode>|<size_est>"]` → `ep_est = medians[key].ep`
2. Fehlt exakter Schnitt: aggregiere alle Einträge mit passendem `<lang>|<cost_mode>` unabhängig von Size → Median der `.ep`-Werte dieser Gruppe.
3. Fehlt auch das: globaler Median aller `.ep`-Werte in `medians` → `ep_est`.
4. Keine `baseline.json` vorhanden oder alle `.ep`-Werte `null`/leer → `ep_est = null` (erwarteter Zustand bis genug Historie).

`ep_est` (und `size_est`) als Session-Variable merken → beim Done in `items.jsonl` eintragen (§2b unten).

Wenn `medians[key].n` < 3: Schnitt vorhanden aber dünn — trotzdem verwenden (kein spezieller Fallback), aber intern notieren (kein User-Output nötig).

## 2. In Progress
- `board set <story-id> status "In Progress"` — setzt die Story auf In Progress.

## 2a. Secret-Sync-Gate (Spec [`docs/architecture/secrets-subsystem.md`](../../docs/architecture/secrets-subsystem.md) §9)

Das Secret-Sync-Gate ist **Teil des regulären `reviewer`-Laufs** (Abschnitt 6a in `agents/reviewer.md`) — kein separater Agent-Dispatch. Der Reviewer prüft im normalen Build-Loop, ob der Diff env-Variablen einführt ohne `.env.example`/`.env.gpg` nachzuziehen. Keine Änderung am Dispatch-Ablauf nötig.

## 2b. Metrik-Erfassung — Ledger-Touchpoints (Spec [`docs/architecture/metrics-subsystem.md`](../../docs/architecture/metrics-subsystem.md) §2–§4)

> **Einziger Schreiber:** Nur `/flow` schreibt `.claude/metrics/dispatches.jsonl` + `items.jsonl` — kein anderer Agent berührt diese Dateien (K2). Erfassung ist deterministische Arithmetik, **~0 zusätzliche LLM-Token**. Jeder Metrik-Fehler wird **still übergangen** (K3) — Messen blockiert nie den Loop und verändert kein Gate.

### Ledger-Verzeichnis
Bei Bedarf `.claude/metrics/` anlegen (falls nicht vorhanden). Schreiben **ausschließlich append-only** (`>>` / `jq -c . >> datei`). Historische Zeilen werden nie gelöscht oder umgeschrieben (Ausnahme: späterer `tok`-Patch durch `metrics-token-collect`).

### Vor jedem Agent-Dispatch (coder / reviewer / dba / tester / cicd)
```bash
T0=$(date -u +%s)
```
Diesen Wert für den nachfolgenden Dispatch-Schlusspunkt merken.

### Nach jedem Agent-Dispatch — eine Zeile nach `dispatches.jsonl`
Aus dem Klartext-Handoff deterministisch zählen (**kein** zweiter LLM-Lauf):

| Feld | Quelle |
|---|---|
| `ts` | `date -u +%Y-%m-%dT%H:%M:%SZ` |
| `item` | Story-ID (`S-###`) |
| `seq` | laufende Dispatch-Nummer **innerhalb** des Items (ab 1 hochzählen) |
| `agent` | `coder` \| `reviewer` \| `dba` \| `tester` \| `cicd` |
| `iter` | N aus `Review-Handoff … (Iteration N)`; bei nicht-Loop-Rollen die zugehörige Iteration |
| `gate` | `PASS` \| `CHANGES-REQUIRED` \| `FAIL` \| `SKIPPED-*` \| `null` (rollen-abhängig) |
| `crit` | #Einträge unter `## Critical` (nur reviewer/dba; sonst 0) |
| `imp` | #Einträge unter `## Important` (nur reviewer/dba; sonst 0) |
| `rule_hits` | Regel-ID-Tags aus den Befunden (z.B. `["coder/R01"]`); keine Tags → `[]` |
| `secs` | `$(date -u +%s) − T0` |
| `tok` | `null` (Phase 0; Befüllung durch `metrics-token-collect`) |
| `cost_mode` | aktiver Cost-Mode dieses Laufs |

Fehlender / nicht parsbarer Marker → Feld `null` / `0` / `[]`, **nie raten**. Zeile wegschreiben, auch wenn einzelne Felder `null` sind.

Beispiel-Append (jq):
```bash
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg item "S-014" --argjson seq 1 \
  --arg agent "coder" --argjson iter 1 \
  --argjson gate 'null' --argjson crit 0 --argjson imp 0 \
  --argjson rule_hits '[]' \
  --argjson secs "$(($(date -u +%s) - T0))" \
  --arg cost_mode "balanced" \
  '{ts:$ts, item:$item, seq:$seq, agent:$agent, iter:$iter,
    gate:$gate, crit:$crit, imp:$imp, rule_hits:$rule_hits,
    secs:$secs, tok:null, cost_mode:$cost_mode}' \
  >> .claude/metrics/dispatches.jsonl || true
```
Das Beispiel zeigt den **coder**-Dispatch (`gate` = `null`, da der coder kein Gate
setzt). Für **reviewer/dba/tester** stattdessen den echten Gate-Wert als String
übergeben — `--arg gate "PASS"` (bzw. `"CHANGES-REQUIRED"` / `"FAIL"` / `"SKIPPED-*"`);
`gate:$gate` im Body bleibt unverändert und ist Schema-konform (`gate: string | null`).
Das `|| true` stellt sicher, dass ein jq-/IO-Fehler den Loop nicht abbricht (K3).

### Beim Done (Item → `Done`, nach Rollout-Gate: PASS) — eine Zeile nach `items.jsonl`

1. **`loc`/`files`** aus `git diff --shortstat` des Item-Diffs gegen `$default_branch`-Stand bei Item-Eintritt: `loc` = insertions + deletions, `files` = #geänderte Dateien.
2. **Aggregation** über alle `dispatches.jsonl`-Zeilen des Items (filter `item == <n>`):
   - `iters` = max der `iter`-Werte
   - `crit` = Σ `crit`
   - `imp` = Σ `imp`
   - `test_fails` = Anzahl Zeilen mit `gate == "FAIL"` und `agent == "tester"`
   - `rule_hits` = Vereinigung aller `rule_hits`-Arrays
   - `secs_total` = Σ `secs` (null-Felder als 0)
3. **EP-Formel** (Startgewichte, es sei denn `baseline.json.weights` vorhanden → diese haben Vorrang):
   ```
   EP = 1
      + 2 · (iters − 1)
      + 1 · crit
      + 0.5 · imp
      + 2 · test_fails
      + round(log10(loc + 1))
      + 3 · blocked
   ```
4. **`blocked`** = 1 wenn das Item zwischenzeitlich den Status `NEEDS-HUMAN`, ungelöste `depends` oder manuellen Eingriff hatte, sonst 0.
5. **Schätzfelder:** `size_est` + `ep_est` aus §1a (beim Item-Eintritt bestimmt, Session-Variable). War §1a nicht ausführbar oder ergab keinen Wert → `size_est = "M"`, `ep_est = null` (K3). `tok` / `tok_total` = `null` (Phase 0, Befüllung durch `metrics-token-collect`).

Felder der `items.jsonl`-Zeile (subsystem §2.2):

| Feld | Wert |
|---|---|
| `ts` | Done-Zeitstempel (ISO-8601 UTC) |
| `item` | Story-ID (`S-###`) |
| `size_est` | aus §1a (Heuristik + ggf. L/XL-Korrektur); Default `"M"` |
| `ep_est` | aus §1a-Mapping über `baseline.json`; `null` wenn keine Baseline |
| `ep_act` | EP nach obiger Formel |
| `iters` | max `iter` der Dispatches |
| `crit` | Σ `crit` |
| `imp` | Σ `imp` |
| `test_fails` | #`Test-Gate: FAIL` |
| `rule_hits` | Vereinigung aller Regel-IDs |
| `loc` | insertions + deletions (shortstat) |
| `files` | #geänderte Dateien (shortstat) |
| `tok_total` | `null` (Phase 0) |
| `secs_total` | Σ `secs` |
| `blocked` | 0 \| 1 |
| `lang` | `profile.lang` (`language:`-Wert aus `.claude/profile.md`) |
| `cost_mode` | aktiver Cost-Mode |

Append analog zu `dispatches.jsonl` mit `|| true` (kein Loop-Abbruch bei Fehler, K3).

### Token-Nachtrag (out-of-band, Spec `metrics-token-collect` V4 / subsystem §4 Schritt 4)

Nach dem Append der `items.jsonl`-Zeile (`tok_total` initial `null`) sofort:

```bash
bash "$REPO_ROOT/scripts/metrics-collect.sh" "$ITEM_NR" >&2 || true
```

Das Script parst die Subagent-Transcript-JSONL, summiert echte Token je Dispatch
und patcht die `tok`-Felder der betroffenen `dispatches.jsonl`-Zeilen + `tok_total`
der `items.jsonl`-Zeile (nur `null`-Felder, bestehende Werte bleiben). Schlägt das
Script fehl oder findet es keine Transcripts → Felder bleiben `null`, **kein Abbruch**,
das Item bleibt `Done` (K3/K4). `REPO_ROOT` = Pfad zum Plugin-Repo (Verzeichnis, das
`scripts/` enthält); bei Dogfooding-Lauf = cwd des agent-flow-Repos.

### Datei-Hygiene (Spec V11 / subsystem §11)
- `dispatches.jsonl` + `items.jsonl`: gitignored (`.gitignore`).
- `baseline.json`: committet (von `retro` gepflegt, analog `LEARNINGS.md`).
- Kein Secret, keine Diff-Inhalte, keine Befund-Prosa im Ledger (K6).

## 3. Build-Loop (max. 3 Iterationen, N = 1..3)

> **Parallele Worktrees — Frische + Hot-Spot-Warnung (flow/P1).** Beim Dispatch von mehreren coder-Tasks parallel oder in schneller Folge: (a) **Worktree-Frische:** weise jeden coder an, `git fetch origin && git reset --hard origin/<default_branch>` auszuführen und das Vorhandensein erwarteter Vorgänger-Artefakte zu verifizieren, bevor er implementiert (`coder/R03`). (b) **Hot-Spot-Files:** wenn mehrere parallele Items dieselben zentralen Wiring-Dateien berühren (z. B. `server.js`-Router-Registrierung, `App.jsx`-Route-Map, `index.ts`-Re-Exporte), serialisiere die betreffenden Items ODER vereinbare ein append-only/Block-Konvention für diese Dateien und plane frühe Rebase-Punkte ein. Unkontrollierte parallele Edits an Hot-Spot-Files erzeugen wiederkehrende Merge-Konflikte. *[seen-in: dev-gui-cloudflare Items #107–#111 (server.js-Router-Overlap, DeployOrchestrator-Duplikat); promoted: 2026-06-09]*

1. **coder** (Task): `TASK #<n>` · `SPEC: docs/specs/<feature>.md (AC<…>)` · `ITERATION: N` · bei N>1 die offenen `FINDINGS`. Er editiert nur den Working-Tree (Code + ggf. kleine Spec-Präzisierung). *(Metrik: §2b T0 vor Dispatch merken; nach Handoff Dispatch-Zeile appenden.)*
2. **reviewer** (Task): `git diff` + die **Spec** (`docs/specs/<feature>.md`, AC<…>). *(Metrik: §2b T0 vor Dispatch merken; nach Handoff Dispatch-Zeile appenden.)* Lies sein `Review-Gate`:
   - `CHANGES-REQUIRED` → Critical+Important als `FINDINGS` merken, N++ → zurück zu 3.1.
   - `PASS` → **DB-Trigger prüfen** (siehe 3.2a). Triggert er → weiter zu 3.2a; sonst → weiter zu 4.
2a. **DBA-Zweit-Review (nur bei DB-Trigger)** — Trigger gilt, wenn **eines** zutrifft (Architektur-Spec §11):
    - Board-Item hat Label `db`, ODER
    - `git diff` berührt `db_scripts/`, `docs/data-model.md`, ODER Datenzugriffscode (Heuristik: Imports von `pg`/`postgres`/`mysql2`/`mariadb`/`better-sqlite3`/`sqlite3`/`mongoose`/`mongodb`/`prisma`/`drizzle`/`supabase`).

    Dann zusätzlich **dba** (Task, Review-Modus): `git diff` + Spec + Item-Label. *(Metrik: §2b T0 vor Dispatch merken; nach Handoff Dispatch-Zeile appenden.)* Lies sein `Review-Gate`:
    - `CHANGES-REQUIRED` → Critical+Important als `FINDINGS` an coder zurück, N++ → 3.1.
    - `PASS` → **beide Gates PASS** → weiter zu 4 (Tester). Pflicht: **beide** Reviews müssen PASS sagen, bevor `tester` läuft.
- **SPEC-LÜCKE:** meldet der coder eine strukturelle/Scope-Lücke (oder der reviewer/dba verweist auf `requirement`) → `board set <id> status Blocked --reason "Spec unvollständig — /requirement nötig"`, dem User melden. Nicht im Loop raten.
- **Schleifenschutz:** überlebt derselbe Befund N=3 → `board set <id> status Blocked --reason "Loop-Schutz N=3 — gleicher Befund überlebt 3 Iterationen"`, melde es dem User, frage ob mit den restlichen Items weiter. Dann 1.

## 4. Test-Gate
- **tester** (Task): Working-Tree + die **Spec** (AC<…>). *(Metrik: §2b T0 vor Dispatch merken; nach Handoff Dispatch-Zeile appenden.)* Lies `Test-Gate`:
  - `FAIL` → als Befund zurück an coder (zählt zum Schleifenschutz) → 3.1.
  - `PASS` → weiter zu 5.
  - `SKIPPED-NO-DOCKER` → **human-handoff** (kein Auto-Merge): `board set <id> status Blocked --reason "DB-Subsystem-Smoke konnte nicht laufen — Docker-Daemon fehlt; bitte lokal mit Docker oder via Remote-Host wiederholen"`, dem User melden, **nicht** zu 5. weitergehen. Wir wissen sonst nicht, ob die Template-Änderung mechanisch funktioniert.
  - `SKIPPED-DOC-ONLY` → äquivalent zu PASS für den Gate-Zweck (Diff ist reine Doku in `tests/db-subsystem/`, kein mechanischer Effekt) → weiter zu 5. Im Normalfall greift der Pfad-Filter in §4 unten schon und der `tester` wird gar nicht dispatcht; dieser Branch ist Defense-in-Depth, falls der `tester` doch lief.

**Template-Diff = hartes Test-Gate.** Wenn `git diff --name-only` (gegen `main`) im `agent-flow`-Repo Pfade unter `templates/_shared/db-*/**`, `templates/_shared/companion-*/**` oder `tests/db-subsystem/*.sh` (nur die Smoke-Skripte selbst, **nicht** README/Docs in dem Ordner) berührt, ist `Test-Gate: PASS` **Pflicht-Vorbedingung** für Schritt 5 — kein Bypass, auch nicht im `direct`-merge-Modus. Reine Doku-Edits (z.B. `tests/db-subsystem/README.md`) triggern das Gate **nicht** — der `tester` hat keinen Smoke für sowas und würde nur einen No-Op zurückgeben (siehe Pfad-Tabelle in `agents/tester.md`). Der `tester`-Agent dispatcht die zugehörigen Smoke-Skripte selbst (Auswahl-Regel siehe `agents/tester.md` → „DB-Subsystem-Smoke (bei Template-Diffs)"). Die früher angedachte CI-Variante (`.github/workflows/smoke-db.yml`) entfällt damit — lokaler Tester-Run ist schneller, kostet keine Actions-Minuten und scheitert nicht an leeren Org-Budgets.

## 5. Landen — delegiert an `cicd` als ausführenden Abschluss-Arm

Nach `tester`-PASS: **`cicd`-Agent** (Task) dispatchen mit dem SHIP-TRIGGER. *(Metrik: §2b T0 vor Dispatch merken; nach Handoff Dispatch-Zeile appenden.)* cicd führt die git-Operationen (merge + push) im Auftrag des Orchestrators durch, beobachtet den CI-Lauf und führt den lokalen Rollout + Disk-Hygiene durch.

**Warum cicd statt Orchestrator-eigene git-Operationen:** der Orchestrator bleibt der konzeptuelle Eigner des Flows und der Board-Übergänge; cicd ist der spezialisierte Ausführungs-Arm für den technischen Abschluss (git + Docker + Prune). Das ist keine Verletzung des „einziger git-Schreiber"-Prinzips — der Orchestrator delegiert explizit (via SHIP-TRIGGER), cicd handelt nicht eigenständig.

- **Post-Rebase-Verifikation (flow/P2):** Nach jeder Rebase- oder Konfliktauflösung — und bevor das Item auf `Done` gesetzt wird — MUSS der volle Test-Run gegen den **finalen main-Stand** bestätigt werden (nicht nur gegen den isolierten Worktree). cicd's CI-Watch (Schritt 3 der ship-Sequenz, `gh run watch` gegen `main`) deckt das im Normalfall ab; bei **lokaler Konfliktauflösung** zusätzlich `profile.build`/`tester` direkt gegen den post-merge `main`-Stand ausführen. Ein Konfliktlöser, der „Tests grün" nur im Worktree-Kontext bestätigt, kann einen main-Stand mit roten Tests hinterlassen (umgeschriebene Tests kommen nicht sauber an / Mismatch Implementierung↔Test). *[seen-in: dev-gui-cloudflare Rebase nach Items #109/#110 (3 rote Tests auf main nach Konfliktauflösung); promoted: 2026-06-09]*

**SHIP-TRIGGER:**
```
SHIP-TRIGGER: #<n> tester-PASS — bitte landen, CI beobachten, lokal ausrollen
BRANCH: item-<n>-<slug>
MERGE_POLICY: <aus profile.merge_policy>
IMAGE: <profile.image>:latest
```

**Was cicd dabei tut (Abschnitt A in `agents/cicd.md`):**
- **Code UND etwaige `docs/specs/`-Deltas im selben Commit/PR** — zusammen oder gar nicht (Drift-Gate-Prinzip, CONCEPT §4d).
- **`direct`-Policy:** merge + push auf `$default_branch`.
- **`pr`-Policy:** Branch pushen + PR öffnen (Fork-sicher: `gh pr create --repo "$repo" --base "$default_branch"` — `$repo` via origin-URL aufgelöst). cicd erstellt den PR, merged ihn NICHT selbst → Orchestrator/User mergt; anschliessend Rollout via `/cicd rollout` oder weiter-getriggertem `ship`.
  - **Sonar:** Beim Fabrik-Default (monatlich + manuell) kein per-PR-`sonar.yml`-Run → **kein Warten**. Opt-in-Blockgate: s. Abschnitt in der alten §5-Logik (unverändert).
- **CI-Watch:** `gh run watch` bis Abschluss. Rot → Rollout unterbleibt, `Rollout-Gate: FAIL`.
- **Lokaler Rollout:** `docker pull` + `docker rm -f` + `docker run`.
- **Disk-Hygiene:** `docker image prune -f` (Pflicht).
- Commit-Message endet mit der `Co-Authored-By`-Zeile (von cicd ausgeführt).

**Orchestrator nach cicd-Rückgabe:**
- `Rollout-Gate: PASS` → `board set <id> status Done` (+ PR/Commit verlinkt) + Test-URL melden. *(Metrik: §2b „Beim Done"-Schritt ausführen — `items.jsonl`-Rollup-Zeile appenden.)*
- `Rollout-Gate: FAIL` → melden + `board set <id> status Blocked --reason "CI rot oder Smoke fehlgeschlagen"`, User fragen.
- `Rollout-Gate: NEEDS-HUMAN` → `board set <id> status Blocked --reason "Manueller Eingriff nötig"`, User vorlegen.

Bei `pr`-Policy und ausstehemdem Merge: `board set <id> status "In Review"` (Orchestrator wartet auf Merge-Signal, dann Done).

## 5a. Validate-Flag-Invalidierung (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §18)
**Nach erfolgreichem Landen** prüfen, ob der gerade gelandete Diff den Validate-Cache invalidiert:

**Trigger.** Eines davon trifft zu:
1. Item-Diff ändert `profile.db_dialect` oder `profile.companions[]` (`yq` vor/nach vergleichen).
2. Item-Diff berührt Pfade, die das **gepullte** Template-Snapshot ersetzen würden: `db_scripts/run-migrations.sh`, `db_scripts/000_init_meta.{sql|js}`, `docker-compose.yml` Diff-Lines innerhalb der `# --- db-<dialect> (…)`- oder `# --- companion-<name> (…)`-Sektion.
3. Plugin-Update wurde gepullt: `git -C "$CLAUDE_PLUGIN_ROOT" log -1 --format=%H templates/_shared/db-<dialect>/` ≠ der in `.claude/profile.md` notierten `adoption_validated_plugin_sha` (falls dort getrackt — best-effort, fehlender Wert = kein Trigger).

**Aktion bei Trigger.**
- `adoption_validated_at: null` in `.claude/profile.md` setzen (Key bleibt — explizites null statt löschen, damit der "wurde mal validiert"-Audit-Trail nicht verloren geht; `/preview` Cache-Check liest `validated_at: null` und fällt auf `CACHE_HIT=false`).
- `adoption_validated_dialect` und `adoption_validated_companions` **unverändert lassen** (Audit-Trail: was war zuletzt validiert).
- **Diesen Profile-Edit als Folge-Commit** auf demselben Branch/PR landen (`chore: invalidate adoption_validated_at (db-setup changed)`) — vor dem `gh pr create` aus §5 oder als amend, falls schon committed.
- Klar-Output:
  ```
  ⚠ DB-Setup geändert (item #<n>) — adoption_validated invalidated.
    Re-validation läuft beim nächsten /preview up (mini, best-effort)
    oder explizit via /adopt re-validate.
  ```

**Kein Trigger.** Items, die nur App-Code/Doku ändern (kein DB-/Companion-Profile-Diff, kein Template-Pfad), lassen das Flag unangetastet — Cache bleibt valide.

## 6. Nächstes
- Zurück zu 1, bis das Board leer ist oder der User stoppt.

## 7. Abschluss-Deploy — wenn das Board leer ist

Hinweis: Wenn §5 den cicd-`ship`-Modus ausführt (Standard, `profile.deploy == docker`), sind CI-Watch + Rollout + Prune bereits in der ship-Sequenz enthalten. §7 ist dann nur eine abschliessende Zusammenfassung. Dieser Abschnitt gilt für Konfigurationen, in denen §5 keinen automatischen Rollout auslöst (z.B. `deploy != docker`) oder wenn der Rollout für ein späteres Board-Ende aufgeschoben wurde.

Nur wenn diesem Lauf mindestens ein Item gelandet ist **und** `profile.deploy == docker` **und** kein Rollout in §5 bereits stattgefunden hat:

**cicd-`ship` wurde in §5 bereits ausgeführt (Standard):** Rollout-Gate-Ergebnis aus §5 übernehmen; hier nur Test-URL melden und stoppen.

**Rollout in §5 aufgeschoben (Ausnahme):**
1. **`cicd`-Agent** (Task) dispatchen:
   ```
   SHIP-TRIGGER: Board leer — bitte landen (falls noch nicht), CI beobachten, lokal ausrollen
   BRANCH: <aktueller Stand>
   MERGE_POLICY: <aus profile>
   IMAGE: <profile.image>:latest
   ```
   Lies `Rollout-Gate`:
   - `PASS` → **Test-URL** aus cicd-Output melden (inkl. Version + Prune-Ergebnis).
   - `FAIL` → melden + überspringen (Hinweis auf `/cicd ship`), Flow NICHT scheitern lassen.
   - `NEEDS-HUMAN` → melden, User vorlegen.
2. **Dev-Preview-Variante** (Mac-Loop, kein produktiver Rollout gewünscht, `DEPLOY_ROLE=local`): die `up`-Logik aus dem **`preview`-Skill** ausführen (`docker pull "${image}:latest"` → `docker run … -p <preview_port>:<container_port>` → Smoke) → **Test-URL** melden. Prune: `docker image prune -f` danach trotzdem ausführen.
   - **Faustregel:** `DEPLOY_ROLE=vps` → cicd-`ship`; `local` ohne expliziten Rollout-Wunsch → preview-Skill + manuelles prune.
3. **Best-effort:** CI rot/Timeout oder Pull `denied` → melden + überspringen, Flow NICHT scheitern lassen (Hinweis auf `/cicd ship` bzw. `/preview up`).

Dann stoppen mit Zusammenfassung (gelandete Items + Test-URL + Version).

## Grenzen
- NUR der Orchestrator schreibt Board-Status; cicd führt die git-Abschluss-Operationen (merge+push) und den Rollout im Auftrag des Orchestrators aus (Delegation via SHIP-TRIGGER).
- Bei Unklarheit oder `Blocked`: dem User vorlegen, nicht raten.
- **Rote Tests NIE als „pre-existing/fremd/nicht mein Scope" abtun ohne Ursachenverifikation.** Ein `Test suite failed to run` / Loader-Parse-Fehler in einer Datei, die kein Item dieses Laufs geändert hat, ist meist ein **Umgebungs-Artefakt** (vergifteter Test-Cache, Haste-Map-Duplikate aus den parallelen Worktrees) — kein fremder Code-Bug. Erst Cache leeren + erneut laufen (`knowledge/js.md` `js/R07`; tester §2a), dann werten. Ein gelandeter „grüner" Lauf darf nie auf einem **maskierten** Symptom beruhen (z.B. den verschmutzten Pfad nur aus der Test-*Auswahl* ausschließen, aber die Wurzel — Modul-/Cache-Vergiftung — stehen lassen).
- **Worktree-Parallelität sauber halten:** Bei isolierten Worktrees (§3-Parallelfälle) sicherstellen, dass der Test-Runner die Worktree-Verzeichnisse aus **Test-Auswahl UND Modul-Auflösung** ignoriert (jest: `testPathIgnorePatterns` + `modulePathIgnorePatterns` für `.claude/worktrees/`). Sonst zieht ein Lauf fremde, teils rote Tests anderer Branches mit und/oder vergiftet den geteilten Cache. Wer Parallel-Worktrees anlegt, verantwortet auch deren Test-Isolation — ein dadurch verursachter roter `main` ist nicht „fremd".
- **Validate-Flag (§5a) nur invalidieren, nicht setzen:** das Setzen von `adoption_validated_at` lebt ausschließlich in `/adopt` §6 (volle Validation mit Coder-Fix-Loop) und `/preview` §6 (Mini-Re-Validate). `/flow` invalidiert nur — kein eigenes Dispatch des `tester` für Adoption-Validate (würde den Build-Loop §3 verzerren).
