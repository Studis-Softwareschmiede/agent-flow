---
id: retro-cooldown-persistence
title: Retro-Cooldown-Stempel zuverlässig im geharvesteten Projekt-Repo persistieren (Schutzgitter G3)
status: draft
version: 1
---

# Spec: Retro-Cooldown-Stempel zuverlässig persistieren  (`retro-cooldown-persistence`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Subsystem-Bindung.** Diese Spec präzisiert das **Schutzgitter G3 (Cooldown)** aus `docs/architecture/framework-build-subsystem.md` §9 Punkt 3. Sie ändert weder die Schwelle (1×/Woche/Repo) noch den State-Ort (`.claude/lessons/.retro-last-run`), sondern schliesst eine **Persistenz-Lücke**: der Stempel-Write muss denselben Commit-Pfad nehmen wie die bereits etablierte `baseline.json`-Persistenz (`agents/retro.md` Modus C / C4).

## Zweck

Schutzgitter G3 begrenzt `retro` auf max. 1 Lauf pro Woche pro geharvestetem Projekt-Repo. Der State ist ein ISO-Datum in `.claude/lessons/.retro-last-run` **im geharvesteten Projekt-Repo**. Heute schreibt `retro` (Schritt 3a) das Datum nur in den Working-Tree, ohne zu garantieren, dass es nach `origin/<default_branch>` des Projekt-Repos persistiert wird. Weil retro-Läufe typischerweise **isoliert** ablaufen (Lessons-Read aus einem Worktree, PR gegen agent-flow via `mktemp`-Klon), landet der Stempel in einem verworfenen Working-Tree und geht verloren → G3 ist wirkungslos. Diese Spec macht die Persistenz testbar und schliesst sie an den bestehenden `baseline.json`-Commit-Pfad an.

## Kontext / Motivation (reale Belege, 2026-06-14/15 — bindend)

- **PR #140 (`retro/dev-gui-parallel-workflow`)** harvestete `dev-gui` am 2026-06-14, ließ `dev-gui:.claude/lessons/.retro-last-run` aber auf `2026-06-08` stehen — der Stempel-Write des Laufs ging im isolierten Tree verloren.
- Der **darauffolgende Lessons-Harvest am 2026-06-15 (→ PR #155)** lief, weil der Stempel `2026-06-08` (= 7 Tage) zeigte — obwohl der echte letzte Lauf nur 1 Tag zurücklag. **G3-Schutz war wirkungslos.** Der Stempel musste manuell per separatem PR (#258 im dev-gui) nachgezogen werden.
- Beim `reviewer`-Check des retro-PRs suchte der reviewer den Stempel fälschlich im **agent-flow-PR-Ziel** statt im **geharvesteten Projekt-Repo** (State-Ort ist nicht eindeutig dokumentiert) → falscher „G3-Violation"-Befund.

## Verhalten

### V1 — Stempel persistiert zuverlässig in den geharvesteten Projekt-Repo
Nach jedem **erfolgreichen** retro-Lauf (Modus A oder B; nicht durch `--force`-Bypass blockiert) MUSS das ISO-Datum von heute in `<projekt-repo>/.claude/lessons/.retro-last-run` geschrieben **und** nach `origin/<default_branch>` des **geharvesteten Projekt-Repos** persistiert werden (Commit + Push gemäss dessen `merge_policy`). Der Write darf NICHT nur in einen Working-Tree erfolgen, der nach dem Lauf verworfen wird.

### V2 — Isolations-fest (Worktree / `mktemp`-Klon)
Die Persistenz MUSS auch dann greifen, wenn der retro-Lauf isoliert ablief: Lessons-Read aus einem git-Worktree und/oder der Pack-PR gegen agent-flow über einen `mktemp`-Klon. Der Stempel-Write zielt **immer** auf das geharvestete Projekt-Repo (cwd / `REPO_ROOT`), nicht auf den agent-flow-PR-Klon und nicht auf einen flüchtigen Read-Worktree.

### V3 — Gleicher Persistenz-Pfad wie `baseline.json` (keine Divergenz)
Der Stempel-Commit/Push nutzt **denselben** Persistenz- und Commit-Mechanismus, mit dem `agents/retro.md` C4 bereits `.claude/metrics/baseline.json` im Projekt-Repo pflegt (Commit nach `origin/<default_branch>` gemäss `merge_policy`). Es entsteht **kein zweiter, divergierender** State-/Commit-Pfad. Wo möglich, fährt der Stempel im **selben Commit** wie eine ohnehin anstehende `baseline.json`-Aktualisierung mit.

### V4 — Eindeutige State-Ort-Dokumentation
Der kanonische State-Ort wird eindeutig dokumentiert: Der Cooldown-Stempel lebt **im geharvesteten Projekt-Repo** unter `.claude/lessons/.retro-last-run` — **nicht** im agent-flow-PR-Ziel. Diese Verortung wird an den maßgeblichen Stellen festgehalten: `agents/retro.md` (Schritt 3a / G3), `skills/retro/SKILL.md` (Schutzgitter 3) und `docs/architecture/framework-build-subsystem.md` §9 Punkt 3.

### V5 — Reviewer/G3-Check sucht am richtigen Ort
Der G3-Check (Schutzgitter 3) sucht/prüft den Stempel **ausschliesslich im geharvesteten Projekt-Repo** (`<projekt-repo>/.claude/lessons/.retro-last-run`), NICHT im agent-flow-PR-Diff/-Ziel. Ein retro-PR gegen agent-flow ist deshalb NICHT als „G3-Violation" zu werten, nur weil der Stempel nicht im PR-Diff auftaucht.

### V6 — Fehlender Stempel = kein Cooldown
Existiert `.retro-last-run` nicht (oder ist leer / kein parsbares ISO-Datum), gilt **kein** Cooldown — der Lauf ist erlaubt (bisheriges Verhalten, unverändert). Erst ein erfolgreicher Lauf erzeugt/aktualisiert den Stempel (V1).

### V7 — Robuste Persistenz ohne Lauf-Abbruch, aber Drift-vermeidend
Schlägt der Stempel-Commit/Push aus IO-/git-Gründen fehl, darf der retro-Lauf **nicht hart abbrechen** (analog K3-Toleranz von Modus C). ABER: der Fehler MUSS sichtbar gemeldet werden (Lauf-Output / PR-Body-Hinweis), damit der Drift-Fall „Lauf erfolgreich, Stempel nicht persistiert" nicht still passiert. Ein erfolgreicher Lauf, dessen Stempel-Write still verworfen wird, ist explizit das zu verhindernde Anti-Verhalten (siehe Belege).

### V8 — Idempotenz
Mehrfaches Schreiben desselben ISO-Datums am selben Tag ist idempotent (kein Fehler, kein Spam-Commit, wenn sich der Inhalt nicht ändert — analog C4-`git diff --quiet`-Gate vor `git add`).

## Acceptance-Kriterien

- **AC1** — Nach einem erfolgreichen retro-Lauf enthält `<projekt-repo>/.claude/lessons/.retro-last-run` das ISO-Datum von heute UND dieser Stand ist nach `origin/<default_branch>` des geharvesteten Projekt-Repos persistiert (Commit + Push gemäss dessen `merge_policy`), nicht nur im Working-Tree. *(V1)*
- **AC2** — Die Persistenz greift auch bei isoliertem Lauf (Lessons-Read aus Worktree und/oder Pack-PR via `mktemp`-Klon): der Stempel-Write zielt nachweislich auf das geharvestete Projekt-Repo (cwd/`REPO_ROOT`), nicht auf den agent-flow-PR-Klon oder einen flüchtigen Read-Worktree. *(V2)*
- **AC3** — Stempel-Persistenz und `baseline.json`-Persistenz teilen sich denselben Commit-/Push-Pfad (C4-Mechanik); es existiert kein zweiter, divergierender State-/Commit-Mechanismus für den Cooldown. *(V3)*
- **AC4** — Der kanonische State-Ort (`<projekt-repo>/.claude/lessons/.retro-last-run`, NICHT agent-flow-PR-Ziel) ist eindeutig dokumentiert in `agents/retro.md` (3a/G3), `skills/retro/SKILL.md` (Schutzgitter 3) und `docs/architecture/framework-build-subsystem.md` §9.3. *(V4)*
- **AC5** — Der G3-Check sucht den Stempel ausschliesslich im geharvesteten Projekt-Repo; ein retro-PR gegen agent-flow wird NICHT allein deshalb als „G3-Violation" gewertet, weil der Stempel nicht im agent-flow-PR-Diff steht. *(V5)*
- **AC6** — Fehlt/leer/unparsbar `.retro-last-run` → kein Cooldown, Lauf erlaubt; erst ein erfolgreicher Lauf erzeugt/aktualisiert den Stempel. *(V6)*
- **AC7** — Scheitert der Stempel-Commit/Push (IO/git), bricht der retro-Lauf NICHT hart ab, meldet den Fehler aber sichtbar (Lauf-Output und/oder PR-Body-Hinweis); ein erfolgreicher Lauf mit still verworfenem Stempel-Write ist ausgeschlossen. *(V7)*
- **AC8** — Wiederholtes Schreiben desselben Datums am selben Tag ist idempotent (kein Fehler, kein Leer-/Doppel-Commit bei unverändertem Inhalt). *(V8)*

## Verträge

| Artefakt | Garantie |
|---|---|
| `<projekt-repo>/.claude/lessons/.retro-last-run` | Kanonischer Cooldown-State. Inhalt: genau **ein** ISO-Datum (`YYYY-MM-DD`) des letzten erfolgreichen retro-Laufs in **diesem** Repo. Geschrieben **ausschliesslich** von `retro` (Single-Writer). Liegt im geharvesteten Projekt-Repo, NIE im agent-flow-PR-Ziel. |
| `agents/retro.md` (Schritt 3a / G3) | Spezifiziert, dass der Stempel-Write nach `origin/<default_branch>` des Projekt-Repos committet+gepusht wird (gemäss `merge_policy`), über den C4-Persistenz-Pfad, isolations-fest (V1–V3, AC1–AC3). Dokumentiert den State-Ort eindeutig (V4/AC4). |
| `skills/retro/SKILL.md` (Schutzgitter 3) | Dokumentiert State-Ort + Persistenz-Garantie eindeutig (V4/AC4). |
| `docs/architecture/framework-build-subsystem.md` §9.3 | Amendment: Stempel-Persistenz-Garantie + State-Ort-Klarstellung; verweist auf diese Spec. |
| `agents/reviewer.md` (G3-Check, falls verortet) | G3-Check sucht im geharvesteten Projekt-Repo, nicht im agent-flow-PR-Diff (V5/AC5). |

**State-Datei-Vertrag:** Genau eine Zeile, ein ISO-Datum `YYYY-MM-DD`. Fehlend/leer/unparsbar ⇒ kein Cooldown (V6). Single-Writer = `retro`.

## Edge-Cases & Fehlerverhalten

- **Isolierter Lauf (Worktree-Read + `mktemp`-Pack-PR):** Stempel zielt auf cwd/`REPO_ROOT` des Projekt-Repos, nicht auf Read-Worktree/PR-Klon (V2/AC2).
- **`--force`-Bypass:** umgeht den Cooldown-Check bewusst; ein erfolgreicher `--force`-Lauf aktualisiert den Stempel dennoch (Persistenz wie V1).
- **Leerer retro-Lauf (kein Pattern reif für Promotion):** zählt als erfolgreich → Stempel wird trotzdem aktualisiert+persistiert (G3 tickt deterministisch bei jedem Lauf; Begründung §9.3-Amendment 2026-05-31). Existiert kein anderer Commit (kein Pack-PR, kein baseline.json-Diff), MUSS der Stempel dennoch nach `origin/<default_branch>` persistiert werden.
- **git-Push-Fehler (Netz/Perms/Konflikt):** kein harter Abbruch, sichtbare Fehlermeldung (V7/AC7).
- **Stempel-Inhalt unverändert (gleicher Tag):** idempotent, kein Leer-Commit (V8/AC8).
- **Repo mit `merge_policy: pr`:** Persistenz folgt der `merge_policy` des Projekt-Repos (analog baseline.json/C4); der Stempel landet nicht direkt auf `main`, wenn das Repo PR-only ist.

## NFRs

- **Robustheit (K3-Toleranz):** Persistenz-Fehler dürfen den retro-Kern-Output (Pack-PR, baseline.json) nicht verlieren — aber den Drift-Fall sichtbar machen (V7).
- **Single-Writer-Disziplin:** `.retro-last-run` wird ausschliesslich von `retro` geschrieben (analog baseline.json/C6).
- **Keine zweite State-Quelle / kein zusätzlicher Bypass** (konsistent mit `agents/retro.md` Harte Grenzen, Modus C/E: „kein zweiter State-Ort, kein zusätzlicher Bypass").

## Nicht-Ziele

- Cooldown-Schwelle ändern (bleibt 1×/Woche/Repo) oder State-Ort verschieben (bleibt `.claude/lessons/.retro-last-run`).
- `--force`-Semantik ändern.
- baseline.json-Aggregation/Inhalt ([[metrics-retro-aggregation]], [[metrics-retro-effectiveness]]).
- Sonar-spezifische G1-Sonar-Schwelle (separat, `agents/retro.md` H3).
- Die übrigen Schutzgitter G1 (Frequenz), G2 (Provenance), G4 (Reviewer-Gate).

## Abhängigkeiten

- `docs/architecture/framework-build-subsystem.md` §9 (Schutzgitter, bindend).
- [[metrics-retro-aggregation]] / [[metrics-retro-effectiveness]] — teilen den C4-Persistenz-Pfad (baseline.json), an den V3 anschliesst.
