---
id: board-ship-pr-merge-worktree-safe
title: board-ship.sh — PR-Merge worktree-fest (kein lokaler Checkout) + Selbstheilung bei bereits gemergtem PR
status: active
area: auslieferung
version: 1
spec_format: use-case-2.0
---

# Spec: board-ship.sh — PR-Merge worktree-fest + Selbstheilung  (`board-ship-pr-merge-worktree-safe`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**.

## Zweck

`board-ship.sh` ist der deterministische SHIP-Pfad (L3, Reaktion auf den
S-047-Datenverlust): sein Wert ist „mechanisch prüfen statt behaupten". Der
**`merge_policy: pr`-Pfad** (der Weg, den **agent-flow selbst** nutzt) hat drei
strukturelle Defekte, die genau die Datenverlust-Klasse wieder aufreissen, gegen
die der SHIP-Pfad gebaut wurde:

1. **Lokaler Aufräum-Schritt scheitert deterministisch im Worktree-Modell.**
   `scripts/board-ship.sh:400` ruft `gh pr merge "$BRANCH" --squash
   --delete-branch`. `--delete-branch` räumt **nach** dem Remote-Merge **lokal**
   auf: es löscht den Story-Branch und schaltet den aufrufenden Worktree auf den
   `default_branch` (`main`). Im Worktree-Modell (`CLAUDE.md`-Pflicht) ist `main`
   **immer** vom Hauptordner belegt — Git verbietet denselben Branch in zwei
   Worktrees. Der lokale Schritt scheitert damit **deterministisch bei jeder
   PR-Landung aus einem Story-Worktree** (7 belegte Fälle: S-074, S-075, S-118,
   S-119, S-098, S-120, S-121). Das ist kein Sporadik-, sondern ein
   Struktur-Fehler — analog zur Worktree-Annahme in
   [[board-ship-environment-guards]] AC7, dort aber nur für den `direct`-Pfad
   gelöst; der `pr`-Pfad (Zeile 394–400) blieb auf `--delete-branch`.
2. **`|| die` unterscheidet Erfolg nicht von Rest-Aufräumen.** Der Guard hinter
   Zeile 400 kann nicht zwischen „Remote-Merge fehlgeschlagen" und „Merge ok,
   nur lokales Aufräumen (`--delete-branch`) gescheitert" unterscheiden. Das
   Skript **stirbt NACH dem Erfolg** — der Remote-Merge ist gelandet, aber die
   Schritte 3–6 (CI-Watch, Board-Flip auf `Done`, `pr`-Feld, Dispo-Mirror)
   entfallen. Ergebnis: die Story ist gemergt, das Board sagt weiter „nicht
   erledigt" — exakt die stille Inkonsistenz, die der L3-Pfad verhindern soll.
3. **Der ALREADY_MERGED-Check ist squash-blind.** Der Idempotenz-Check
   (Zeile 362, `git merge-base --is-ancestor "$LOCAL_HEAD" "origin/…"`) fragt, ob
   der Story-Commit ein **Vorfahre** des Ziel-Branches ist. Nach einem
   **Squash**-Merge ist der Story-Commit **kein** Vorfahre von `main` (Squash
   erzeugt einen neuen, einzelnen Commit). Ein Re-Run (nach dem Tod aus Defekt 2)
   erkennt die bereits erfolgte Landung darum **nicht** und würde erneut landen —
   Leer-PR-Gefahr bzw. Doppel-Merge (vgl. flow/L02, flow/L06).

Diese Spec macht den `pr`-Merge-Pfad **worktree-fest** (Remote-Merge ohne lokale
git-Nebenwirkungen), lässt das Skript den Remote-PR-Zustand **befragen** statt
lokales Aufräumen mit dem Merge-Erfolg zu verwechseln, und macht den
„bereits gemergt?"-Check **squash-tauglich** — ohne die bestehenden `direct`- und
`--target-branch`-Pfade zu berühren.

## Main Success Scenario

1. `/flow` ruft nach tester-PASS `board-ship.sh <S-###>` aus dem
   **Story-Worktree** auf; `merge_policy: pr`, Ziel ist der `default_branch`
   (`main`), der im Hauptordner belegt ist.
2. Das Skript stellt fest, dass der PR noch nicht gemergt ist (squash-tauglicher
   Check, AC2), erstellt den PR und mergt ihn **ohne lokale git-Nebenwirkungen**
   (GitHub-seitiger Squash-Merge, **kein** `--delete-branch`, **kein** Checkout —
   AC1).
3. Der Remote-Branch wird nach dem Merge **serverseitig** gelöscht (API, kein
   lokaler Checkout — AC4).
4. CI-Watch (unverändert nach [[board-ship-environment-guards]]), Rollout (nur
   echter Ziel-Branch), Board-Flip auf `Done` + `pr`-Feld + Dispo — alles im
   vorhandenen Temp-Detached-Worktree-Mechanismus (AC3), auch bei belegtem
   `main`.
5. Exit 0. Der aufrufende Worktree steht unverändert auf dem Story-Branch; der
   Hauptordner wurde nie berührt.

## Alternative Flows

### A1: Remote-Merge ok, aber der Merge-Aufruf meldet einen nicht-null Exit (z.B. Rest-Aufräumen scheitert)
- Das Skript **stirbt nicht** am Exit-Code allein. Es befragt den Remote-PR-Zustand
  (`gh pr view --json state,mergedAt`). Ist der Zustand `MERGED` (bzw.
  `mergedAt` gesetzt) → **Erfolg**, weiter mit Schritt 3/4/5. (AC2)

### A2: Re-Run nach Squash-Merge (PR bereits gemergt)
- Der squash-taugliche „bereits gemergt?"-Check (PR-Status statt nur
  `merge-base`) erkennt die Landung → **kein** zweiter PR, **kein** zweiter
  Merge; direkt weiter mit CI-Watch/Board-Flip (Idempotenz). (AC2, AC5)

### E1: Remote-Merge wirklich fehlgeschlagen (PR nicht MERGED)
- `gh pr view` meldet einen Nicht-`MERGED`-Zustand (`OPEN`/`CLOSED` ohne
  `mergedAt`) → das Skript bricht mit Exit 1 und Klartext-Diagnose ab; **kein**
  Board-Flip. Ein Abbruch, der Merge-Erfolg vortäuscht, ist ausgeschlossen (K1).

## Acceptance-Kriterien

- **AC1** — **PR-Merge ohne lokale git-Nebenwirkungen:** Im `merge_policy:
  pr`-Pfad erfolgt der Merge GitHub-seitig **ohne** `--delete-branch` und **ohne**
  Checkout/Branch-Wechsel im aufrufenden Worktree. Nach dem Merge-Schritt steht
  der aufrufende Worktree unverändert auf dem Story-Branch (HEAD wie beim
  Aufruf); der Zustand des Hauptordners (belegt `main` o.ä.) ist für das Gelingen
  **irrelevant**. Kein Pfad führt `gh pr merge … --delete-branch` mehr aus,
  solange dessen Löschung lokal wirkt.
- **AC2** — **Merge-Erfolg am Remote-PR-Zustand festmachen + squash-tauglicher
  Idempotenz-Check:** (a) Nach dem Merge-Aufruf wird bei nicht-null Exit **nicht**
  sofort `die` ausgeführt, sondern der Remote-PR-Zustand geprüft
  (`gh pr view <pr> --json state,mergedAt`); ist er `MERGED` (bzw. `mergedAt`
  gesetzt), gilt der Merge als **erfolgreich** und der Lauf fährt fort (deckt A1).
  (b) Der „bereits gemergt?"-Check wird squash-tauglich: er stützt sich auf den
  **PR-Status** (`gh pr view … state/mergedAt`), nicht allein auf
  `git merge-base --is-ancestor` — ein per Squash gelandeter, im Ziel-Branch
  **nicht** als Vorfahre enthaltener Story-Commit wird als „gemergt" erkannt
  (deckt A2). Der bestehende `merge-base`-Pfad bleibt als schneller Vorab-Treffer
  erhalten (Defense-in-Depth), ist aber nicht mehr das **einzige** Kriterium.
- **AC3** — **Nacharbeit erledigt das Skript selbst:** Board-Flip (`status:
  Done`), `pr`-Feld, Board-`git commit` + Push und der Dispo-Mirror laufen nach
  erfolgreichem/als erfolgreich erkanntem Merge **selbständig** im vorhandenen
  Temp-Detached-Worktree-Mechanismus (`create_temp_land_worktree`, vgl.
  [[board-ship-environment-guards]] AC9) — auch bei belegtem `main`. Ein
  erfolgreicher Remote-Merge führt **nie** dazu, dass das Skript vor dem
  Board-Flip stirbt (Defekt 2 geschlossen).
- **AC4** — **Remote-Branch-Löschung via API:** Die Löschung des Story-Branches
  nach dem Merge erfolgt serverseitig (GitHub-API bzw. `gh`-Äquivalent ohne
  lokalen Checkout) und ist **nicht-fatal** — schlägt sie fehl (z.B. Branch
  bereits weg, fehlende Rechte), bricht der Lauf **nicht** ab und der Board-Flip
  findet trotzdem statt. Kein Pfad löscht den Branch über einen lokalen
  Checkout/`git branch -d` im aufrufenden Worktree.
- **AC5** — **Testabdeckung (`tests/board-ship/run-test.sh`, Fixture-Stil, mit
  den bestehenden `MOCK_*`-Mocks):**
  (a) **Worktree-belegt-`main`, PR-Policy:** Fixture mit bare-Origin und `main`
  in einem **zweiten** Worktree belegt; `board-ship.sh S-###` (Modus A,
  `merge_policy: pr`) läuft mit **Exit 0** durch, der Story-Commit ist auf
  `origin/main`, der Board-Flip auf `Done` ist im `origin/main`-Stand enthalten,
  und der zweite Worktree steht danach unverändert auf `main` (HEAD +
  Working-Tree unberührt).
  (b) **Squash-Re-Run:** Ein bereits per Squash gemergter PR (Story-Commit
  **nicht** Vorfahre von `origin/main`) führt beim erneuten Aufruf zu **Exit 0**
  **ohne** einen zweiten PR/Merge; CI-Watch (bzw. dessen Entfall) und Board-Flip
  laufen idempotent (deckt A2).
  (c) **Merge-ok-Cleanup-Fehler:** Der Merge-Aufruf meldet nicht-null Exit,
  `gh pr view` liefert aber `state=MERGED`/`mergedAt` gesetzt → **Exit 0**,
  Board-Flip findet statt (deckt A1). Umgekehrt: nicht-`MERGED` → **Exit 1**,
  **kein** Board-Flip (deckt E1).
- **AC6** — **`--target-branch`-/Feature-Pfad und `merge_policy: direct` bleiben
  unverändert:** Diese Spec ändert **nur** den `merge_policy: pr`-Zweig (heute
  Zeilen 394–400) und den Idempotenz-Check (Zeile 362, squash-tauglich, ohne den
  `merge-base`-Vorab-Treffer zu entfernen). Der `direct`-Pfad (AC8 aus
  [[board-ship-environment-guards]]), der `--target-branch`-/Feature-Pfad (Modus
  B) und Modus C bleiben in Verhalten und Exit-Codes bitgenau wie heute; ihre
  bestehenden Tests bleiben unverändert grün.

> **Traceability:** Tests tragen `@trace board-ship-pr-merge-worktree-safe#AC<n>`,
> soweit der Fixture-Stil (`tests/board-ship/run-test.sh`, gemocktes `gh`) das
> trägt — die Abdeckung wird über die benannten Testfälle in AC5 nachgewiesen.

## Verträge

- **CLI-Oberfläche unverändert:** Aufrufformen, Argumente, Modi A/B/C und
  Exit-Codes (0 = gelandet/bereits gelandet, 1 = Abbruch) bleiben wie in
  [[feature-batch-orchestration]] / [[board-ship-environment-guards]]. Diese Spec
  ändert **nur** das Innere des `pr`-Merge-Zweigs.
- **Merge-Weg (`merge_policy: pr`):** PR erstellen (`gh pr create`, unverändert),
  dann Merge **serverseitig** ohne lokale Nebenwirkung (kein `--delete-branch`
  mit lokaler Wirkung, kein Checkout). Erfolgsfeststellung: nicht-null Exit ⇒
  `gh pr view <pr> --json state,mergedAt`; `state == MERGED` **oder** `mergedAt`
  nicht null ⇒ Erfolg.
- **Idempotenz-Feststellung:** „bereits gemergt" = PR-Status `MERGED`/`mergedAt`
  gesetzt (squash-tauglich) **oder** `git merge-base --is-ancestor` trifft
  (schneller Vorab-Treffer, Nicht-Squash).
- **Branch-Löschung:** serverseitig, nicht-fatal (Board-Flip läuft auch bei
  Löschfehler).
- **Board-Flip-Ergebnis:** unverändert `status: Done`, `branch: <story-branch>`,
  `pr: <url>`, committet als `chore(board): <S-###> Done` im Ziel-Branch, im
  Temp-Detached-Worktree (AC9 aus [[board-ship-environment-guards]]).

## Edge-Cases & Fehlerverhalten

- **E1 — Remote-Merge wirklich fehlgeschlagen** (`gh pr view` ≠ `MERGED`, kein
  `mergedAt`): Exit 1 mit Klartext, **kein** Board-Flip; `origin` unverändert.
- **E2 — `gh pr view` selbst schlägt fehl** (Netz/Auth/Rate-Limit) nach nicht-null
  Merge-Exit: gilt **nicht** als Merge-Erfolg (fail-safe, K1) — Abbruch mit
  Klartext, damit ein erneuter idempotenter Aufruf (A2) die Landung sauber
  feststellt statt sie zu erraten. `ensure_gh_auth` greift wie heute vorab.
- **E3 — Branch-Löschung schlägt fehl:** nicht-fatal (AC4) — Logzeile, Board-Flip
  läuft weiter.
- **E4 — Board-Flip-Push scheitert, weil `origin/main` inzwischen weitergelaufen
  ist:** Abbruch (Exit 1), **kein** Force, **kein** `reset`. Der Merge ist
  gelandet, der Flip nicht — ein erneuter, idempotenter Aufruf (A2) holt ihn nach
  (identisch zu E6 in [[board-ship-environment-guards]]).
- **E5 — L6-Guard:** `guard_clean_or_die` bleibt vor **jedem**
  `fetch`/`push`/Merge-Schritt im aufrufenden Worktree unverändert der harte
  Boden (S-047).

## NFRs

- **Kein stiller Board-Drift (der Zweck der Story):** Ein erfolgreicher
  Remote-Merge führt **nie** zu „gemergt, aber Board nicht `Done`". Genau diese
  Inkonsistenz (Merge ok, Skript stirbt am lokalen Aufräumen, Schritte 3–6
  entfallen) war der belegte Defekt in 7 Fällen.
- **Sicherheit vor Bequemlichkeit (K1):** Jede Unklarheit über den Merge-Zustand
  (`gh pr view` unklar/fehlgeschlagen) endet in „sichtbar abbrechen", nie in
  „Erfolg annehmen".
- **Determinismus:** reines Bash, kein LLM-Urteil; die Merge-/Idempotenz-Frage
  wird aus dem **beobachteten Remote-PR-Zustand** beantwortet, nicht behauptet.

## Nicht-Ziele

- **CI-Watch-Verhalten** (Beobachtungsfenster, `default_branch`-Schärfe) — bleibt
  unverändert wie in [[board-ship-environment-guards]] (AC1–AC6); diese Spec
  berührt es nicht.
- **`merge_policy: direct`-Pfad** — unverändert (dort gibt es keinen
  `gh pr merge`, kein `--delete-branch`; die Worktree-Festigkeit ist dort bereits
  über AC7/AC8 aus [[board-ship-environment-guards]] gelöst).
- **Automatischer Rebase im Non-FF-/Konflikt-Fall** — kein Ziel; der sichtbare
  Abbruch bleibt.
- **Rückbefüllung** der 7 historischen Fälle (S-074 …) — die sind manuell
  nachgearbeitet; diese Spec verhindert die Wiederholung, migriert nichts.

## Abhängigkeiten

- [[board-ship-environment-guards]] — **Schwester-Spec**: dort AC7 (kein Checkout
  des Ziel-Branches) + AC9 (Board-Flip im Temp-Detached-Worktree) für den
  `direct`-Pfad. Diese Spec zieht **dieselbe** Worktree-Festigkeit in den bislang
  ausgesparten `pr`-Merge-Zweig (Zeile 394–400) und nutzt denselben
  Temp-Worktree-Mechanismus (`create_temp_land_worktree`) für die Nacharbeit.
- [[feature-batch-orchestration]] — Modus-A/B/C-Verträge, `--target-branch`; von
  dieser Spec unangetastet (AC6).
- Quelle der Diagnose: belegte Fälle S-074, S-075, S-118, S-119, S-098, S-120,
  S-121 (lokales `--delete-branch`-Aufräumen scheiterte im Worktree-Modell);
  flow/L02, flow/L06 (Squash-Blindheit des Idempotenz-Checks → Leer-PR-Gefahr).
</content>
</invoke>
