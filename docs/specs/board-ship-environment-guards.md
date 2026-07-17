---
id: board-ship-environment-guards
title: board-ship.sh — Umgebungs-Vorbedingungen prüfen statt annehmen (Branch-CI, Worktree)
status: active
area: auslieferung
version: 2
spec_format: use-case-2.0
---

<!--
v2 (Owner-Entscheid 2026-07-17) — Ansatzwechsel bei AC1–AC6 (Bug 1, CI-Watch).
v1 verlangte, die Trigger-Frage aus `.github/workflows/*` **herzuleiten**. Der
coder baute dafür einen Eigenbau-YAML-Parser in Bash; zwei Review-Iterationen
brachten zwei kritische, end-to-end reproduzierte Fail-open-Fälle — beide mit
demselben Fehlermodus „roter CI auf main wird durchgewunken":
(1) `branches: &default_branches` (Anker auf dem `branches:`-Key) → no-trigger;
(2) `on: &on_cfg` (Anker auf dem `on:`-Key) → no-trigger, Board-Flip lief trotz
roter Mock-CI durch. Dazu: quotierte Globs (`"*-hotfix"`) sind nach dem
Quote-Stripping nicht mehr von echten Aliassen unterscheidbar.
Befund: Bash kann YAML nicht — jeder Flicken deckt den gemeldeten Fall, die
Fehlerklasse bleibt offen. Verworfen wurde der **Ansatz**, nicht das Ziel:
v2 beantwortet die Trigger-Frage **empirisch** (nachsehen, ob für die eigene
SHA ein Run erscheint) statt sie herzuleiten. AC7–AC13 (Bug 2) unverändert.
-->


# Spec: board-ship.sh — Umgebungs-Vorbedingungen prüfen statt annehmen  (`board-ship-environment-guards`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**.

## Zweck

`board-ship.sh` ist der deterministische SHIP-Pfad: sein Wert ist „mechanisch
prüfen statt behaupten" (L3, Reaktion auf den S-047-Datenverlust). Zwei
**Umgebungsannahmen** prüft es bisher nicht — und scheitert an beiden
strukturell, nicht sporadisch:

1. **CI-Annahme:** es prüft „hat das *Repo* Workflows?" (`workflow_count`),
   handelt aber so, als hätte es „triggert ein Workflow auf *diesem
   Branch*?" geprüft. Bei `main`-only-CI + Feature-Branch-Strategie wartet es
   10 Minuten auf einen Lauf, der strukturell nie erscheint, und `die`t dann —
   obwohl der Merge längst gelandet ist. Der Board-Flip (Schritt 5/6)
   unterbleibt. Verifiziert in dev-gui durch drei Läufe (S-351, S-352, S-353) —
   **alle drei mit `--target-branch feature/F-080`**, keiner auf `main`.
   Die Frage wird **empirisch** beantwortet (erscheint für die eigene SHA ein
   Run?), nicht aus den Workflow-Definitionen hergeleitet — siehe v2-Notiz oben.
2. **Worktree-Annahme:** es checkt den Ziel-Branch im aufrufenden Working-Tree
   aus. Git verbietet denselben Branch in zwei Worktrees — hält der Hauptordner
   `main`, kann Modus A aus einem Story-Worktree **nie** landen
   (`fatal: a branch named 'main' already exists`). Das ist der **Normalfall**:
   `CLAUDE.md` verpflichtet in agent-flow **und** dev-gui jede schreibende
   Session auf einen eigenen Worktree. Verifiziert 2026-07-16 (dev-gui, S-358).

Beide Male stirbt das Skript an einer Umgebung, die es nicht befragt hat. Diese
Spec macht die zwei Annahmen zu **mechanischen Prüfungen** — ohne die
Schärfe des CI-Gates auf `main` und ohne den L6-Guard aufzuweichen.

## Main Success Scenario

1. `/flow` ruft nach tester-PASS `board-ship.sh <S-###> [<container>]
   [--target-branch <branch>]` im **Story-Worktree** auf.
2. Das Skript prüft den Working-Tree (L6-Guard), landet den Story-Commit im
   Ziel-Branch — **ohne** den Ziel-Branch im aufrufenden Worktree
   auszuchecken.
3. Es sieht **nach**, ob für die gelandete **eigene** Ziel-SHA auf dem
   Ziel-Branch ein CI-Run erscheint (kurzes Beobachtungsfenster). Erscheint
   einer, wird er unverändert scharf bis zur `conclusion` beobachtet.
   Erscheint auf einem **Nicht-`default_branch`** keiner, gibt es dort keinen
   Trigger — der Watch entfällt ohne Fehler.
4. Rollout (nur beim echten Ziel-Branch), Board-Flip, Board-Commit + Push.
5. Der aufrufende Worktree steht am Ende unverändert auf dem Story-Branch; der
   Hauptordner wurde nie berührt.

## Alternative Flows

### A1: Ziel-Branch hat keine triggernde CI (z.B. `feature/F-###` bei `main`-only-CI)
- Ziel-Branch ≠ `default_branch`; innerhalb des Beobachtungsfensters erscheint
  **kein** Run mit der eigenen Ziel-SHA.
- Logzeile, `return 0` — **kein** Sleep bis 40×15 s, **kein** `die`. Weiter mit
  Schritt 4/5/6 (Board-Flip findet statt).

### A2: `merge_policy: direct`, Fast-Forward möglich
- `git push origin HEAD:<ship-branch>` landet ohne lokalen Checkout.

### E1: `merge_policy: direct`, **kein** Fast-Forward (origin ist voraus)
- Kein Push, kein Merge-Commit, kein `reset`. Abbruch (Exit 1) mit
  Klartext-Diagnose — jemand anders war schneller, ein Rebase ist eine
  Owner-/Orchestrator-Entscheidung. Entspricht dem heutigen
  `merge --ff-only`-Abbruch.

### E2: Kein Run für die eigene SHA — aber Ziel ist der `default_branch`
- **Konservativ**: **kein** Skip. Auf `main` ist ein Trigger der Normalfall;
  „kein Run" ist dort ein **Symptom** (Actions-Störung, Auth, Rate-Limit), kein
  Zustand. Verhalten wie heute: Warteschleife bis Timeout, dann `die` — kein
  Rollout, kein Board-Flip (K1).

### E3: Roter CI auf dem Ziel-Branch
- Unverändert: `die`, **kein** Rollout, **kein** Board-Flip.

## Acceptance-Kriterien

<!-- Teil 1 — Branch-bezogener CI-Guard (flow/L02, dev-gui S-351/S-352/S-353) -->

- **AC1** — **Empirische Trigger-Feststellung (nachsehen statt herleiten):**
  Nach dem Push beobachtet `watch_ci_or_die` bis zu `<grace>` Sekunden (AC5),
  ob auf dem Ziel-Branch ein CI-Run **für die eigene Ziel-SHA** erscheint. Die
  Zuordnung erfolgt **ausschließlich** über den Vergleich `headSha` ==
  eigene Ziel-SHA (`gh run list --branch <branch> --json headSha`, derselbe
  Race-Schutz wie heute). Erscheint ein solcher Run → weiter mit AC2 (scharfer
  Watch). Erscheint **keiner** und ist der Ziel-Branch **nicht** der
  `default_branch` → der Watch entfällt: Logzeile in Klartext (kein CI-Run für
  `<sha>` auf `<branch>` innerhalb `<grace>`s — kein Trigger), `return 0`,
  **kein** weiteres Warten, **kein** `die`; der Aufrufer fährt mit
  Rollout/Board-Flip fort (deckt A1).
  **Ausgeschlossen:** Das Skript liest, parst oder interpretiert
  `.github/workflows/*` in **keiner** Form — weder ganz noch teilweise, weder
  mit `grep`/`sed`/`awk` noch mit einem YAML-Parser. Die Trigger-Frage wird
  **nur** aus beobachteten Runs beantwortet (Owner-Entscheid 2026-07-17).
- **AC2** — **`default_branch` bleibt immer scharf — dort **kein** Skip:**
  Ist der Ziel-Branch der `default_branch` (Modus A **und** Modus C), gibt es
  **kein** Überspringen aufgrund des Beobachtungsfensters. Erscheint ein Run
  für die eigene SHA → unveränderter Watch bis `completed`, `die` bei
  `conclusion != success` inkl. bestehender Meldung (deckt E3). Erscheint
  **keiner** → **unverändertes heutiges Verhalten**: Warteschleife bis Timeout,
  dann `die` — kein Rollout, kein Board-Flip (deckt E2). Ein roter oder
  ausstehender CI-Lauf auf `main` wird durch AC1 unter **keinen** Umständen
  durchgewunken. *(Begründung s. NFR „Asymmetrischer Blast-Radius".)*
- **AC3** — **Fail-safe-Richtung — jede Unsicherheit führt zum scharfen Watch
  (K1):** Ein Run, dessen `headSha` **nicht** die eigene Ziel-SHA ist (z.B. der
  Run des Vorgänger-Commits), gilt weder als „eigener Run" (kein Auswerten
  seiner `conclusion`) **noch** als „kein Run" (er beendet die Beobachtung
  nicht) — er wird schlicht ignoriert, das Fenster läuft weiter. Eine
  fehlgeschlagene oder leere `gh`-Abfrage (Netz, Auth, Rate-Limit) gilt
  **nie** als „kein Trigger": `ensure_gh_auth` + Weiterbeobachten wie heute.
  Der Skip aus AC1 ist **nur** zulässig, wenn die Abfragen im Fenster
  fehlerfrei liefen und dabei durchgehend kein Run mit der eigenen SHA sichtbar
  war.
- **AC4** — **Repos ganz ohne Workflows** verhalten sich unverändert: der
  bestehende Guard (`gh api …/actions/workflows` → `total_count == 0`) greift
  **vor** dem Beobachtungsfenster und lässt den Watch **sofort** entfallen —
  auch auf dem `default_branch`, ohne `<grace>`-Wartezeit. Das ist eine
  API-**Tatsache** über das Repo (keine Herleitung aus Definitionen) und
  bleibt der Pfad für Repos wie agent-flow selbst (`language: md`, kein
  `.github/workflows/`).
- **AC5** — **Beobachtungsfenster: konfigurierbar, aber nie ergebnis-steuernd:**
  Die Fensterlänge ist über eine Env-Variable einstellbar
  (`BOARD_SHIP_CI_GRACE_SECS`), **Default 90 Sekunden**. Ein fehlender,
  nicht-numerischer, negativer oder `0`-Wert fällt auf den Default zurück
  (eine Fehlkonfiguration darf **nie** zu einem sofortigen Skip führen). Der
  Schalter steuert **ausschließlich die Beobachtungsdauer**, nie das Ergebnis:
  es gibt **keinen** Wert und **keinen** weiteren Schalter, der den CI-Watch
  abschaltet, einen Skip auf dem `default_branch` erlaubt (AC2) oder einen
  gefundenen Run ungeprüft lässt.
- **AC6** — **Testabdeckung (`tests/board-ship/run-test.sh`, Fixture-Stil, mit
  den bestehenden `MOCK_*`-Mocks; `BOARD_SHIP_CI_GRACE_SECS` klein gesetzt,
  damit die Suite schnell bleibt):**
  (a) **Skip auf Feature-Branch:** Ship mit `--target-branch feature/F-900`,
  Mock liefert **keinen** Run mit der eigenen SHA → Exit 0, Skip-Logzeile,
  Laufzeit deutlich unter dem alten 40×15 s-Timeout, Board im Feature-Branch
  auf `Done`.
  (b) **`main` bleibt scharf bei rotem CI:** Ship nach `main`, Mock liefert
  einen Run mit der eigenen SHA und `conclusion=failure` → `die` mit „CI nicht
  erfolgreich", Board-Status unverändert (kein Flip).
  (c) **`main` bleibt scharf ohne Run:** Ship nach `main`, Mock liefert
  **keinen** Run mit der eigenen SHA → **kein** Skip, **kein** Board-Flip; das
  Skript endet mit dem Timeout-`die` (AC2/E2).
  (d) **Race-Schutz:** Mock liefert einen Run mit **fremder** `headSha` und
  `conclusion=failure` → dieser Run wird weder als eigener ausgewertet noch als
  „kein Run" verbucht (AC3); auf `main` folgt der Timeout-`die`, kein Flip.
  Die YAML-Anker-/Alias-Regressionsfixtures des verworfenen Parser-Ansatzes
  (Test 10) entfallen ersatzlos — sie sichern eine Lösung ab, die es nicht mehr
  gibt.

<!-- Teil 2 — Worktree-taugliches Landen (flow/L07, dev-gui S-358) -->

- **AC7** — **Kein Checkout des Ziel-Branches:** In **keinem** Pfad (Modus A, B
  oder C) führt `board-ship.sh` `git checkout <ship-branch>` bzw.
  `git checkout -b <ship-branch>` im **aufrufenden** Working-Tree aus. Nach
  jedem Ausgang (Erfolg wie Abbruch) steht der aufrufende Worktree unverändert
  auf dem Story-Branch mit demselben HEAD wie beim Aufruf. Ein Lauf aus einem
  Story-Worktree, während der Hauptordner `<ship-branch>` hält, ist damit der
  **reguläre** Fall und landet regulär.
- **AC8** — **Landen bei `merge_policy: direct` per FF-Push:** Nach
  `guard_clean_or_die` + `git fetch origin <ship-branch>` wird mechanisch
  geprüft, ob ein Fast-Forward möglich ist (`git rev-list --count
  HEAD..origin/<ship-branch>` == 0). Ist es das, landet
  `git push origin HEAD:<ship-branch>` — ohne Checkout, ohne `pull`, ohne
  `reset` (deckt A2). Ist der Zähler > 0, erfolgt **kein** Push: Exit 1 mit
  Klartext-Diagnose (kein FF möglich, `<n>` Commits Rückstand gegenüber
  `origin/<ship-branch>`, manuell rebasen) — `origin/<ship-branch>` bleibt
  unverändert, Board bleibt unverändert (deckt E1). Das entspricht dem
  heutigen `merge --ff-only`-Abbruch; ein automatischer Merge-Commit entsteht
  hier **nicht**.
- **AC9** — **Board-Flip ohne Ziel-Branch-Checkout:** Der Board-Flip (Schritt
  5/6: `board set … status Done`, `branch`, ggf. `pr`, Commit `board/`, Push)
  passiert in einem **temporären, detached Worktree** auf
  `origin/<ship-branch>` (`git worktree add --detach`) und landet per
  `git push origin HEAD:<ship-branch>`. Der temporäre Worktree wird auf
  **jedem** Ausgang (Erfolg, Fehler, Abbruch) wieder entfernt
  (`git worktree remove` + `prune`) — kein Rest im Repo, kein verwaister
  Eintrag in `git worktree list`. Inhalt und Reihenfolge des Flips sind
  identisch zu heute (Flip **nach** grünem/entfallenem CI-Watch, nie davor).
- **AC10** — **Modus C (`--merge-feature`) ebenfalls worktree-tauglich:** Der
  finale Feature-Merge nach `<default_branch>` erfolgt ohne `checkout` und ohne
  `reset --hard` des `<default_branch>` im aufrufenden Worktree; der
  Merge-Commit (`--no-ff`, unverändert kein Squash) entsteht im temporären
  Worktree aus AC9 und landet per Push. Idempotenz-Pfad („bereits vollständig
  enthalten", `merge-base --is-ancestor`) bleibt unverändert.
- **AC11** — **L6-Guard unangetastet:** `guard_clean_or_die` läuft unverändert
  vor **jedem** `fetch`/`push`/Merge-Schritt im aufrufenden Worktree; ein
  dirty Working-Tree bricht **vor** jedem git-Zugriff ab, `origin` bleibt
  unverändert. Der Guard wird durch AC7–AC10 weder entfernt noch übersprungen.
- **AC12** — **Verbotene Operationen:** Kein Pfad des Skripts verwendet
  `git push --force`/`-f`/`--force-with-lease`; kein Pfad führt
  `git reset --hard` auf einem Branch aus, der im aufrufenden Worktree
  ausgecheckt ist. Ein non-fast-forward-Push scheitert **sichtbar** (Exit 1),
  statt still zu überschreiben.
- **AC13** — **Testabdeckung (`tests/board-ship/run-test.sh`, Fixture-Stil):**
  (a) Eine Fixture mit einem **zweiten Worktree**, der `main` hält, belegt:
  `board-ship.sh S-900` aus dem Story-Worktree (Modus A, `merge_policy:
  direct`) läuft mit Exit 0 durch, der Story-Commit ist auf `origin/main`, der
  Board-Flip auf `Done` ist im `origin/main`-Stand enthalten, und der zweite
  Worktree steht danach unverändert auf `main` (HEAD + Working-Tree
  unberührt).
  (b) Non-FF-Fall: liegt auf `origin/main` ein fremder Commit, der nicht im
  Story-Branch enthalten ist, endet der Lauf mit Exit 1 und Klartext-Meldung;
  `origin/main` unverändert, Board-Status **nicht** `Done`.
  (c) Die bestehenden Tests 1–8 bleiben unverändert grün (L6-Guard,
  merge-base-Erkennung, Happy Path, CI-Gate, Idempotenz, Modus B, Modus C,
  `default_branch`-Fallback).

> **Traceability:** Tests tragen `@trace board-ship-environment-guards#AC<n>`,
> soweit die Testart (`tests/board-ship/run-test.sh`, Bash-Fixtures mit
> gemocktem `gh`) das trägt — die Abdeckung wird über die benannten
> Testfälle in AC6/AC13 nachgewiesen, nicht über ein separates Test-Framework.

## Verträge

- **CLI-Oberfläche unverändert:** Aufrufformen, Argumente, Modi A/B/C, Exit-Codes
  (0 = gelandet/bereits gelandet, 1 = Abbruch) und die bestehenden Log-/
  Fehlermeldungen bleiben wie in [[feature-batch-orchestration]] (Verträge,
  „`board-ship.sh`-Erweiterung (drei Modi)") beschrieben. Diese Spec ändert
  **nur** die Umgebungsprüfungen im Inneren.
- **Aufrufer-Vertrag:** `/flow` und `board-feature-drain.sh` rufen das Skript
  unverändert auf. Neu **garantiert** ist: der Aufruf ist aus einem
  Story-Worktree zulässig, auch wenn der Ziel-Branch anderswo ausgecheckt ist
  (AC7).
- **Env-Variablen:** `BOARD_SHIP_SKIP_GH_AUTH=1` (Test-Seam, unverändert) und
  neu `BOARD_SHIP_CI_GRACE_SECS` (Beobachtungsfenster, Default 90, AC5).
  Es entsteht **kein** Env-Schalter zum Überspringen oder Abschalten des
  CI-Watch — ob übersprungen wird, entscheidet allein die Beobachtung (AC1)
  plus die harte `default_branch`-Regel (AC2).
- **Board-Flip-Ergebnis:** unverändert `status: Done`, `branch: <story-branch>`,
  `pr: <url>` (nur PR-Policy), committet als `chore(board): <S-###> Done` im
  Ziel-Branch.

## Edge-Cases & Fehlerverhalten

- **E4 — Ziel-Branch existiert remote noch nicht** (Modus B, Feature-Branch):
  unverändert — Abzweig von `origin/<default_branch>` per Push
  (Defense-in-Depth, kein Checkout nötig).
- **E5 — Story bereits gemergt** (`merge-base --is-ancestor` trifft): kein
  zweiter Merge; CI-Watch (bzw. dessen Entfall nach AC1) und Board-Flip laufen
  wie heute weiter — Idempotenz bleibt (Test 2/5). Der Run zur bereits
  gelandeten SHA ist dann i.d.R. längst `completed` und wird sofort im Fenster
  gefunden — der Skip greift hier also **nicht**, die `conclusion` wird
  regulär geprüft.
- **E9 — GitHub legt den Run langsamer an als `<grace>`** (das bewusst
  eingegangene Restrisiko dieses Ansatzes, s. NFR): Auf einem
  Nicht-`default_branch` überspringt das Skript dann fälschlich einen echten
  CI-Lauf. Bewusst akzeptiert, weil (a) die beobachtete Praxis Runs binnen
  **Sekunden** anlegt (die *Laufzeit* von 5–8 Min ist irrelevant — gewartet
  wird nur auf das **Erscheinen**), (b) der Default von 90 s eine Größenordnung
  darüber liegt, (c) der Blast-Radius klein ist (Modus B rollt nie aus; das
  Gate der Einzel-Story ist der `tester`), und (d) `main` davon nach AC2
  **nie** betroffen ist — ein übersehener Feature-Branch-Lauf fiele spätestens
  beim finalen `--merge-feature` auf `main` auf, wo scharf gewartet wird.
  Gegenmittel bei Bedarf: `BOARD_SHIP_CI_GRACE_SECS` hochsetzen (AC5).
- **E6 — Push des Board-Flips scheitert, weil `origin/<ship-branch>` inzwischen
  weitergelaufen ist:** Abbruch mit Klartext (Exit 1), **kein** Force, **kein**
  Retry-Loop mit `reset`. Der Story-Commit ist dann gelandet, der Flip nicht —
  ein erneuter, idempotenter Aufruf holt ihn nach (E5).
- **E7 — `git worktree add` schlägt fehl** (z.B. Pfad belegt, Rest eines
  abgebrochenen Laufs): Abbruch mit Klartext statt Fallback auf `checkout` —
  ein Fallback wäre genau der Defekt, den diese Spec beseitigt. Vorheriges
  `git worktree prune` ist zulässig (nicht-destruktiv, entfernt nur verwaiste
  Metadaten).
- **E8 — Aufruf aus dem Hauptordner** (kein Worktree, Ziel-Branch nirgends
  belegt): funktioniert unverändert — der neue Pfad ist **kein** Sonderfall
  für Worktrees, sondern der einheitliche Weg für beide Umgebungen.

## NFRs

- **Kein Leerlauf (der Nutzen der Story):** Ein Ship auf einen Feature-Branch
  ohne triggernde CI kostet statt 40×15 s = **10 min** nur noch das
  Beobachtungsfenster (Default **90 s**), und der Board-Flip findet statt. Das
  ist der gesamte Zweck von Bug 1 — der verifizierte Fall (S-351/S-352/S-353)
  ist genau dieser.
- **Asymmetrischer Blast-Radius (Begründung für AC2):** Ein falscher Skip wiegt
  auf den beiden Branch-Arten **nicht** gleich schwer. Auf dem
  `default_branch` bedeutet er: ungeprüfter Code wird **ausgerollt** (Modus A/C
  deployen) — genau der Worst Case, an dem beide Parser-Versuche gescheitert
  sind. Auf einem Feature-Branch bedeutet er: ein Board-Flip ohne
  CI-Bestätigung, **kein** Rollout (Modus B rollt per Design nie aus), und der
  Code passiert später ohnehin das scharfe `main`-Gate. Darum ist das
  Überspringen **exakt dort erlaubt, wo der Bug verifiziert auftrat** — und
  nirgends sonst. Das hält den Skip zugleich innerhalb des gemeldeten Scopes.
- **Sicherheit vor Bequemlichkeit:** Jede Unklarheit endet in „scharf prüfen"
  bzw. „sichtbar abbrechen", nie in „überspringen" (K1). Der L6-Guard bleibt
  der harte Boden (S-047).
- **Determinismus + Wartbarkeit:** Das Skript bleibt reines Bash ohne
  LLM-Urteil — und ohne eine Sprache zu parsen, die Bash nicht parsen kann
  (v2-Notiz). Beobachten ist robust gegen jede zulässige YAML-Schreibweise
  (Anker, Aliasse, Globs, Matrix, wiederverwendbare Workflows), weil es die
  Definition gar nicht erst befragt.

## Nicht-Ziele

- **Parallelisierung der Story-Schleife in `board-feature-drain.sh`** — explizit
  ausgeschlossen, eigener Owner-Entscheid (Auftrag 2026-07-17).
- **Automatischer Merge-Commit / Rebase im Non-FF-Fall** (Modus A `direct`):
  bewusst **nicht** Teil dieser Spec — der sichtbare Abbruch ist das heutige
  und gewollte Verhalten (E1). Eine spätere Erweiterung wäre eine eigene
  Spec-Fortschreibung.
- `.github/workflows/*` eines Projekts auf `feature/**` erweitern, um das
  Skript zufriedenzustellen (kostet Actions-Minuten pro Story; die Bündelung am
  Feature-Ende ist Absicht).
- Neue Env-Schalter zum Abschalten von CI-Watch oder Guards.
- **Jede Form von YAML-Auswertung der Workflow-Definitionen** (Eigenbau-Parser,
  `grep`-Heuristik, externe Abhängigkeit wie `yq`) — verworfener Ansatz,
  Owner-Entscheid 2026-07-17 (AC1, v2-Notiz).
- **Überspringen des CI-Watch auf dem `default_branch`** — auch dann nicht,
  wenn dort nachweislich kein Trigger existiert (Ausnahme allein AC4: Repo hat
  überhaupt keine Workflows). Der 10-Minuten-Leerlauf eines hypothetischen
  Repos mit reiner PR-CI bleibt damit bestehen; das ist der bewusst gezahlte
  Preis für „main niemals fail-open" und war nie Teil des gemeldeten Bugs.

## Abhängigkeiten

- [[feature-batch-orchestration]] — Modus-A/B/C-Verträge, `--target-branch`/
  `--merge-feature`; diese Spec lässt deren AC1–AC16 unverändert und schärft
  nur die Umgebungsprüfungen des aufgerufenen Skripts.
- [[flow-session-rotation]] / [[flow-lessons-landing]] — der SHIP-Schritt des
  `/flow`-Vertrags ruft `board-ship.sh` unverändert auf.
- Quelle der Diagnose: `dev-gui/.claude/lessons/flow.md` → `flow/L02`
  (S-351/S-352/S-353) und `flow/L07` (S-358). Beide Lessons sind die lokalen
  Umgehungen; diese Spec ist die strukturelle Kur.
