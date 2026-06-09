---
name: flow
description: Orchestriert die Softwareschmiede — liest das Projekt-Board und arbeitet die To-Do-Items Punkt für Punkt ab (coder → reviewer ⇄ Loop → tester → cicd ship → Done). Einziger Schreiber von Board-Status. Git-Abschluss-Operationen (merge+push) delegiert /flow an cicd als ausführenden Abschluss-Arm. Im Ziel-Projekt-Repo ausführen.
---

# /flow [--cost <mode>] — Board abarbeiten (Orchestrator)

Du bist der **Orchestrator** (Haupt-Session). Du dispatchst die Agenten via Task-Tool und bist der **einzige Schreiber** von Board-Status. Git/PR-Operationen im Abschluss werden an `cicd` als ausführenden Arm delegiert (s. §5). cwd = Ziel-Projekt-Repo.

**Cost-Mode (Token-Hebel).** Jeder Agent-Dispatch dieses Laufs erhält einen **`model`-Override** gemäß dem aktiven Cost-Modus (in §0 aufgelöst). Aufruf optional mit `--cost <low-cost|balanced|max-quality>` (Kurz: `low`/`max`). Im Modus `balanced` wird **kein** Override gesetzt (Agent-Frontmatter gilt). Matrix + Auflösungsregeln: `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md`.

## 0. Setup
- `.claude/profile.md` lesen → Board-Referenz, `merge_policy` (`pr`|`direct`), Build/Test-Befehle, **`default_branch`**, **`cost_mode`** (Default `balanced`).
- **Cost-Mode auflösen** (einmal, merken — gilt für ALLE Dispatches dieses Laufs): Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced`. Kurzformen normalisieren (`low`→`low-cost`, `max`/`high`→`max-quality`). Unbekannter Wert → `balanced` + einzeiliger Hinweis. **Beim Task-Dispatch jedes Agenten** (coder/reviewer/dba/tester in §3–§4 sowie **cicd** beim SHIP-Dispatch in §5) den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Zeile = Rolle, Spalte = Modus) mitgeben; bei `balanced` **keinen** `model`-Parameter setzen (Frontmatter gilt). Einmal zu Beginn ausgeben: „⚙ Cost-Mode: <mode>".
- **Arbeits-Repo Fork-sicher auflösen** (einmal, merken): Das Arbeits-Repo ist **`origin`**. ⚠️ `gh repo view` **ohne Argument** liefert bei einem Fork das **Upstream-Parent** (gh bevorzugt den `upstream`-Remote) — deshalb IMMER die origin-URL explizit übergeben:
  - `repo="$(gh repo view "$(git remote get-url origin)" --json nameWithOwner -q .nameWithOwner)"`
  - Fehlt `profile.default_branch` (Alt-Repo): `default_branch="$(gh repo view "$(git remote get-url origin)" --json defaultBranchRef -q .defaultBranchRef.name)"` (NICHT `main` annehmen — adoptierte Forks haben oft `master`).
- **Auth herstellen:** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token aus `.env.gpg`, loggt `gh` ein). **NICHT `gh auth login --web`.**
- **Security-Frische (einmaliger Nudge):** `last_trained:` aus `${CLAUDE_PLUGIN_ROOT}/knowledge/security.md` lesen; ist es **> 90 Tage** her → einmal ausgeben: „🔒 security-Pack ist <N> Tage alt — `/train security` erwägen." (nur Hinweis, blockiert nicht).

## 1. Nächstes Item wählen
- `gh project item-list …` → das **To-Do**-Item mit höchster Priority, dessen **Depends-on** alle `Done` sind.
- Aus dem Item-Body die **Spec-Referenz** lesen: `Spec: docs/specs/<feature>.md` + `implements: AC<…>` — die reichst du an coder/reviewer/tester durch (Source of Truth, nicht der Item-Titel).
- Keins → weiter zu **7. Abschluss-Deploy** (statt sofort stoppen).

## 2. In Progress
- Board-Item-Status → **In Progress**.

## 3. Build-Loop (max. 3 Iterationen, N = 1..3)

> **Parallele Worktrees — Frische + Hot-Spot-Warnung (flow/P1).** Beim Dispatch von mehreren coder-Tasks parallel oder in schneller Folge: (a) **Worktree-Frische:** weise jeden coder an, `git fetch origin && git reset --hard origin/<default_branch>` auszuführen und das Vorhandensein erwarteter Vorgänger-Artefakte zu verifizieren, bevor er implementiert (`coder/R03`). (b) **Hot-Spot-Files:** wenn mehrere parallele Items dieselben zentralen Wiring-Dateien berühren (z. B. `server.js`-Router-Registrierung, `App.jsx`-Route-Map, `index.ts`-Re-Exporte), serialisiere die betreffenden Items ODER vereinbare ein append-only/Block-Konvention für diese Dateien und plane frühe Rebase-Punkte ein. Unkontrollierte parallele Edits an Hot-Spot-Files erzeugen wiederkehrende Merge-Konflikte. *[seen-in: dev-gui-cloudflare Items #107–#111 (server.js-Router-Overlap, DeployOrchestrator-Duplikat); promoted: 2026-06-09]*

1. **coder** (Task): `TASK #<n>` · `SPEC: docs/specs/<feature>.md (AC<…>)` · `ITERATION: N` · bei N>1 die offenen `FINDINGS`. Er editiert nur den Working-Tree (Code + ggf. kleine Spec-Präzisierung).
2. **reviewer** (Task): `git diff` + die **Spec** (`docs/specs/<feature>.md`, AC<…>). Lies sein `Review-Gate`:
   - `CHANGES-REQUIRED` → Critical+Important als `FINDINGS` merken, N++ → zurück zu 3.1.
   - `PASS` → **DB-Trigger prüfen** (siehe 3.2a). Triggert er → weiter zu 3.2a; sonst → weiter zu 4.
2a. **DBA-Zweit-Review (nur bei DB-Trigger)** — Trigger gilt, wenn **eines** zutrifft (Architektur-Spec §11):
    - Board-Item hat Label `db`, ODER
    - `git diff` berührt `db_scripts/`, `docs/data-model.md`, ODER Datenzugriffscode (Heuristik: Imports von `pg`/`postgres`/`mysql2`/`mariadb`/`better-sqlite3`/`sqlite3`/`mongoose`/`mongodb`/`prisma`/`drizzle`/`supabase`).

    Dann zusätzlich **dba** (Task, Review-Modus): `git diff` + Spec + Item-Label. Lies sein `Review-Gate`:
    - `CHANGES-REQUIRED` → Critical+Important als `FINDINGS` an coder zurück, N++ → 3.1.
    - `PASS` → **beide Gates PASS** → weiter zu 4 (Tester). Pflicht: **beide** Reviews müssen PASS sagen, bevor `tester` läuft.
- **SPEC-LÜCKE:** meldet der coder eine strukturelle/Scope-Lücke (oder der reviewer/dba verweist auf `requirement`) → Item → **Blocked** (+ Kommentar „Spec unvollständig — `/requirement` nötig"), dem User melden. Nicht im Loop raten.
- **Schleifenschutz:** überlebt derselbe Befund N=3 → Item → **Blocked** (+ Kommentar), melde es dem User, frage ob mit den restlichen Items weiter. Dann 1.

## 4. Test-Gate
- **tester** (Task): Working-Tree + die **Spec** (AC<…>). Lies `Test-Gate`:
  - `FAIL` → als Befund zurück an coder (zählt zum Schleifenschutz) → 3.1.
  - `PASS` → weiter zu 5.
  - `SKIPPED-NO-DOCKER` → **human-handoff** (kein Auto-Merge): Item → **Blocked** (Kommentar „DB-Subsystem-Smoke konnte nicht laufen — Docker-Daemon fehlt; bitte lokal mit Docker oder via Remote-Host wiederholen"), dem User melden, **nicht** zu 5. weitergehen. Wir wissen sonst nicht, ob die Template-Änderung mechanisch funktioniert.
  - `SKIPPED-DOC-ONLY` → äquivalent zu PASS für den Gate-Zweck (Diff ist reine Doku in `tests/db-subsystem/`, kein mechanischer Effekt) → weiter zu 5. Im Normalfall greift der Pfad-Filter in §4 unten schon und der `tester` wird gar nicht dispatcht; dieser Branch ist Defense-in-Depth, falls der `tester` doch lief.

**Template-Diff = hartes Test-Gate.** Wenn `git diff --name-only` (gegen `main`) im `agent-flow`-Repo Pfade unter `templates/_shared/db-*/**`, `templates/_shared/companion-*/**` oder `tests/db-subsystem/*.sh` (nur die Smoke-Skripte selbst, **nicht** README/Docs in dem Ordner) berührt, ist `Test-Gate: PASS` **Pflicht-Vorbedingung** für Schritt 5 — kein Bypass, auch nicht im `direct`-merge-Modus. Reine Doku-Edits (z.B. `tests/db-subsystem/README.md`) triggern das Gate **nicht** — der `tester` hat keinen Smoke für sowas und würde nur einen No-Op zurückgeben (siehe Pfad-Tabelle in `agents/tester.md`). Der `tester`-Agent dispatcht die zugehörigen Smoke-Skripte selbst (Auswahl-Regel siehe `agents/tester.md` → „DB-Subsystem-Smoke (bei Template-Diffs)"). Die früher angedachte CI-Variante (`.github/workflows/smoke-db.yml`) entfällt damit — lokaler Tester-Run ist schneller, kostet keine Actions-Minuten und scheitert nicht an leeren Org-Budgets.

## 5. Landen — delegiert an `cicd` als ausführenden Abschluss-Arm

Nach `tester`-PASS: **`cicd`-Agent** (Task) dispatchen mit dem SHIP-TRIGGER. cicd führt die git-Operationen (merge + push) im Auftrag des Orchestrators durch, beobachtet den CI-Lauf und führt den lokalen Rollout + Disk-Hygiene durch.

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
- `Rollout-Gate: PASS` → Item → **Done** (+ PR/Commit verlinkt) + Test-URL melden.
- `Rollout-Gate: FAIL` → melden + Item → **Blocked** (Kommentar: CI rot oder Smoke fehlgeschlagen), User fragen.
- `Rollout-Gate: NEEDS-HUMAN` → Item → **Blocked**, User vorlegen.

Bei `pr`-Policy und ausstehemdem Merge: Item → **In Review** (Orchestrator wartet auf Merge-Signal, dann Done).

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
