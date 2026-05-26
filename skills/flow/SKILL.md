---
name: flow
description: Orchestriert die Softwareschmiede — liest das Projekt-Board und arbeitet die To-Do-Items Punkt für Punkt ab (coder → reviewer ⇄ Loop → tester → landen → Done). Einziger Schreiber von Board-Status und git/PR. Im Ziel-Projekt-Repo ausführen.
---

# /flow — Board abarbeiten (Orchestrator)

Du bist der **Orchestrator** (Haupt-Session). Du dispatchst die Agenten via Task-Tool und bist der **einzige Schreiber** von Board-Status und git/PR. cwd = Ziel-Projekt-Repo.

## 0. Setup
- `.claude/profile.md` lesen → Board-Referenz, `merge_policy` (`pr`|`direct`), Build/Test-Befehle.
- **Auth herstellen:** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token aus `.env.gpg`, loggt `gh` ein). **NICHT `gh auth login --web`.**

## 1. Nächstes Item wählen
- `gh project item-list …` → das **To-Do**-Item mit höchster Priority, dessen **Depends-on** alle `Done` sind.
- Keins → weiter zu **7. Abschluss-Deploy** (statt sofort stoppen).

## 2. In Progress
- Board-Item-Status → **In Progress**.

## 3. Build-Loop (max. 3 Iterationen, N = 1..3)
1. **coder** (Task): `TASK #<n>` · `ACCEPTANCE` · `ITERATION: N` · bei N>1 die offenen `FINDINGS`. Er editiert nur den Working-Tree.
2. **reviewer** (Task): `git diff` + Acceptance. Lies sein `Review-Gate`:
   - `CHANGES-REQUIRED` → Critical+Important als `FINDINGS` merken, N++ → zurück zu 3.1.
   - `PASS` → weiter zu 4.
- **Schleifenschutz:** überlebt derselbe Befund N=3 → Item → **Blocked** (+ Kommentar), melde es dem User, frage ob mit den restlichen Items weiter. Dann 1.

## 4. Test-Gate
- **tester** (Task): Working-Tree + Acceptance. Lies `Test-Gate`:
  - `FAIL` → als Befund zurück an coder (zählt zum Schleifenschutz) → 3.1.
  - `PASS` → weiter zu 5.

## 5. Landen (gemäß `merge_policy`)
- **`pr`:** Branch `item-<n>-<slug>` → commit (Message aus Item-Titel + coder-Summary) → push → `gh pr create` → Item → **In Review**. Nach deinem Merge → **Done** (+ PR verlinkt).
- **`direct`:** commit auf `main` → push → Item → **Done** (+ Commit verlinkt).
- Commit-Message endet mit der `Co-Authored-By`-Zeile.

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
