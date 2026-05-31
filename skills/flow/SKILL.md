---
name: flow
description: Orchestriert die Softwareschmiede — liest das Projekt-Board und arbeitet die To-Do-Items Punkt für Punkt ab (coder → reviewer ⇄ Loop → tester → landen → Done). Einziger Schreiber von Board-Status und git/PR. Im Ziel-Projekt-Repo ausführen.
---

# /flow — Board abarbeiten (Orchestrator)

Du bist der **Orchestrator** (Haupt-Session). Du dispatchst die Agenten via Task-Tool und bist der **einzige Schreiber** von Board-Status und git/PR. cwd = Ziel-Projekt-Repo.

## 0. Setup
- `.claude/profile.md` lesen → Board-Referenz, `merge_policy` (`pr`|`direct`), Build/Test-Befehle.
- **Auth herstellen:** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token aus `.env.gpg`, loggt `gh` ein). **NICHT `gh auth login --web`.**
- **Security-Frische (einmaliger Nudge):** `last_trained:` aus `${CLAUDE_PLUGIN_ROOT}/knowledge/security.md` lesen; ist es **> 90 Tage** her → einmal ausgeben: „🔒 security-Pack ist <N> Tage alt — `/train security` erwägen." (nur Hinweis, blockiert nicht).

## 1. Nächstes Item wählen
- `gh project item-list …` → das **To-Do**-Item mit höchster Priority, dessen **Depends-on** alle `Done` sind.
- Aus dem Item-Body die **Spec-Referenz** lesen: `Spec: docs/specs/<feature>.md` + `implements: AC<…>` — die reichst du an coder/reviewer/tester durch (Source of Truth, nicht der Item-Titel).
- Keins → weiter zu **7. Abschluss-Deploy** (statt sofort stoppen).

## 2. In Progress
- Board-Item-Status → **In Progress**.

## 3. Build-Loop (max. 3 Iterationen, N = 1..3)
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

## 5. Landen (gemäß `merge_policy`)
- **Code UND etwaige `docs/specs/`-Deltas im selben Commit/PR** — zusammen oder gar nicht (Drift-Gate-Prinzip, CONCEPT §4d).
- **`pr`:** Branch `item-<n>-<slug>` → commit (Message aus Item-Titel + coder-Summary) → push → `gh pr create` → Item → **In Review**. Nach deinem Merge → **Done** (+ PR verlinkt).
- **`direct`:** commit auf `main` → push → Item → **Done** (+ Commit verlinkt).
- Commit-Message endet mit der `Co-Authored-By`-Zeile.

## 5a. Validate-Flag-Invalidierung (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §18)
**Nach erfolgreichem Landen** prüfen, ob der gerade gelandete Diff den Validate-Cache invalidiert:

**Trigger.** Eines davon trifft zu:
1. Item-Diff ändert `profile.db_dialect` oder `profile.companions[]` (`yq` vor/nach vergleichen).
2. Item-Diff berührt Pfade, die das **gepullte** Template-Snapshot ersetzen würden: `db_scripts/run-migrations.sh`, `db_scripts/000_init_meta.{sql|js}`, `docker-compose.yml` Diff-Lines innerhalb der `# --- db-<dialect> (…)`- oder `# --- companion-<name> (…)`-Sektion.
3. Plugin-Update wurde gepullt: `git -C "$CLAUDE_PLUGIN_ROOT" log -1 --format=%H templates/_shared/db-<dialect>/` ≠ der in `.claude/profile.md` notierten `adoption_validated_plugin_sha` (falls dort getrackt — best-effort, fehlender Wert = kein Trigger).

**Aktion bei Trigger.**
- `adoption_validated_at: null` in `.claude/profile.md` setzen (Key bleibt — explizites null statt löschen, damit der "wurde mal validiert"-Audit-Trail nicht verloren geht; `/preview` Cache-Check liest `validated_at: ""` und fällt auf `CACHE_HIT=false`).
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

## 7. Abschluss-Deploy (Preview) — wenn das Board leer ist
Nur wenn diesem Lauf mindestens ein Item gelandet ist **und** `profile.deploy == docker`:
1. **Auf CI warten:** der letzte Merge triggert `build.yml` (Image → ghcr). `gh run watch "$(gh run list --repo <repo> --branch main --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status` (best-effort, kurzes Timeout).
2. **Preview hochfahren:** die `up`-Logik aus dem **`preview`-Skill** ausführen (`docker pull "${image}:latest"` → `docker run … -p <preview_port>:<container_port>` → Smoke; zsh: Image-Ref immer mit `${…}`) → **Test-URL** melden (`local`: `http://localhost:<port>` · `vps`: `https://<app>.<domain>`).
3. **Best-effort:** CI rot/Timeout oder Pull `denied` → melden + überspringen, den Flow NICHT scheitern lassen (Hinweis auf `/preview up`).

Dann stoppen mit Zusammenfassung (gelandete Items + Test-URL).

## Grenzen
- NUR der Orchestrator schreibt Board-Status + committet/PRt; die Agenten editieren nur / berichten.
- Bei Unklarheit oder `Blocked`: dem User vorlegen, nicht raten.
- **Validate-Flag (§5a) nur invalidieren, nicht setzen:** das Setzen von `adoption_validated_at` lebt ausschließlich in `/adopt` §6 (volle Validation mit Coder-Fix-Loop) und `/preview` §6 (Mini-Re-Validate). `/flow` invalidiert nur — kein eigenes Dispatch des `tester` für Adoption-Validate (würde den Build-Loop §3 verzerren).
