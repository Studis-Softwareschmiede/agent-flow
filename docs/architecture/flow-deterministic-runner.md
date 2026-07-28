# Detailkonzept: Deterministischer /flow-Runden-Runner (Kontext-Diät Stufe 3)

> **Bindend.** Detail-/Architektur-Konzept zu `docs/specs/flow-deterministic-runner.md` (AC1–AC11).
> Source of Truth für den technischen Entwurf: Zustandsautomat, Klassifikations-Tabelle je Ermessensfall, Skript-Schnitt, Minimal-Kontext-Verträge, Fehler-/Eskalationspfade.
> Diese Datei entwirft die Zustandsmaschine, die die Spec bewusst offen liess. Sie ändert **kein** Verhalten der Spec und **keine** Board-/Gate-Semantik — sie verlagert die Ausführungsökonomie (AC9/AC10).
> **Konformität ist Review-Kriterium** (Drift-Gate): Jede Mechanisierung eines heutigen Ermessensfalls MUSS einen in §1 klassifizierten Eskalations-Ausgang haben (AC6/AC7).

Status: entschieden (Owner, 28.07.2026, alle 7 Fragen §9 per Empfehlung a) · Autor: architekt · Datum: 2026-07-28 · Confidence: hoch
Reevaluations-Trigger: (1) `claude -p`-Subsession-Kosten weichen von der board-feature-drain-Erfahrung ab; (2) Gate-Token-Format in coder/reviewer/tester ändert sich; (3) `board next`/`board-ship.sh`-Verträge ändern sich.

---

## 0. Kernentscheidung (ADR-0, MADR-kurz)

**Kontext.** Heute hält der LLM-Orchestrator (`/flow`, eine Haupt-Session) über eine ganze Runde hinweg einen wachsenden Kontext: die vollständige `skills/flow/SKILL.md` (657 Zeilen) plus den kumulierten Gesprächsverlauf werden bei praktisch **jedem** Werkzeug-Schritt neu aus dem Cache gelesen. Der Standard-Pfad einer Runde (Item wählen → claimen → coder→reviewer→tester → landen) ist jedoch fast vollständig **mechanisch** — er braucht kein LLM-Urteil, sondern nur Text-Muster-Auswertung und Git/Board-CLI-Aufrufe.

**Entscheidung.** Ein **deterministischer Bash-Zustandsautomat** (`scripts/board-round.sh`, Arbeitstitel) übernimmt die Standard-Runde. Er dispatcht `coder`/`reviewer`/`tester` als **je eigene, headless `claude -p`-Subsessions mit minimalem Kontext** — exakt das bereits im Feld bewährte Modell aus `scripts/board-feature-drain.sh` (dort auf Story-Ebene: ein `claude -p /flow` pro Story), nur **eine Ebene tiefer**: pro Agent-Dispatch eine Subsession, statt eines grossen LLM-Orchestrators über die Runde. Der Runner selbst hält **keinen** LLM-Kontext — er ist reines Bash. Der LLM-Orchestrator bleibt für **echte Ermessensfälle** (Klasse c, §1) erhalten und wird vom Runner **punktuell** gerufen (Eskalation, §5).

**Warum nicht der `board-feature-drain`-Grobschnitt genügt.** `board-feature-drain.sh` startet je Story eine volle `/flow`-LLM-Session — genau die teure Session, die diese Feature eliminieren will. Der Runner ersetzt den **Rumpf** einer solchen Session durch Bash und lässt nur die 3 Arbeits-Agenten als isolierte Subsessions laufen.

**Konsequenz.**
- Positiv: kein wiederholtes Voll-Lesen der `SKILL.md`/des Verlaufs je Werkzeug-Schritt (AC10); jede Subsession startet mit minimalem, fixem Kontext (AC2); erhaltenes Verhalten aller Sonderfälle über die Klassifikations-Tabelle + Eskalation (AC6/AC9).
- Negativ / Risiko (zentral, S-047-Doktrin): Stufe 3 verlagert Ermessen von LLM auf Skript-Mustererkennung. Ein Fehler ist **unsichtbar** (falsch gelandete/übergangene Story), nicht laut wie ein Crash. **Genau deshalb** ist §1 (die erschöpfende Klassifikation mit definiertem Eskalations-Ausgang je mechanisiertem Schritt) die zentrale Risiko-Kontrolle dieser Feature — nicht der Zustandsautomat selbst.

**Grundsatz (aus `board-ship.sh` K1, übertragen auf jeden neuen mechanisierten Schritt):** *Der Runner behauptet nichts, er prüft. Bei jeder Unklarheit: Abbruch/Eskalation statt Raten — nie ein stiller Default.*

**Anti-Ziel (Scope-Grenze des ersten Runner-Schnitts).** Der Runner deckt die **board-weite Standard-Einzelrunde** ab (genau ein bereites Item, keine Sonderfälle). Ausdrücklich **nicht** im ersten Schnitt: `--all` (interaktive Schleife), `--parent`-Feature-Batch, `--plan`-Wellenplan, SR1-Parallel-Dispatch (Hot-Spot-Analyse), interaktive Design-Freigabe. Diese laufen unverändert über den LLM-Orchestrator (bzw. `board-feature-drain.sh`). Begründung: kleinster Blast-Radius, jede ausgeschlossene Domäne enthält mindestens einen Klasse-(c)-Fall (§1).

---

## 1. Erschöpfte Klassifikations-Tabelle (AC6 — Kern-Garantie)

Legende der drei Stufen (Spec AC6):
- **(a) rein mechanisch** — Bash/Git/Board-CLI + Textmuster, kein LLM. **Jeder (a)-Fall trägt trotzdem einen Eskalations-Ausgang** (AC7): trifft das erwartete Muster nicht eindeutig zu → Abbruch/Eskalation, **nie** Default-Raten.
- **(b) mechanisch mit Eskalations-Fallback** — mechanischer Normalpfad, aber ein definierter Zweig ruft ein leichtes LLM-Urteil (§5) oder den Owner.
- **(c) zwingend LLM-Ermessen** — bleibt beim LLM-Orchestrator/Agenten; der Runner ruft, entscheidet nicht.

Die Tabelle ist **erschöpfend** über `skills/flow/SKILL.md` geführt; die 20 Pflicht-Minimum-Einträge der Spec sind enthalten und mit `[Pflicht #n]` markiert.

### 1.1 Setup (§0)

| # | Ermessensfall | Klasse | Mechanik / Trigger | Eskalations-Ausgang (AC7) |
|---|---|---|---|---|
| S0.1 | `METRICS_ROOT` verankern + Plausibilitäts-Gate (`board/board.yaml`) | **a** | `git rev-parse --show-toplevel`, Datei-Existenz | Gate scheitert → Metrik diese Session mit einem Hinweis überspringen (K3, bestehendes Verhalten) |
| S0.2 | `profile.md` lesen (merge_policy, default_branch, cost_mode, …) | **a** | `grep`/`yq` auf Frontmatter | Feld fehlt → dokumentierter Default (wie heute), kein Raten auf `frontier` |
| S0.3 | Cost-Mode auflösen + `model`-Override je Dispatch | **a** | Präzedenz `--cost` > `profile` > `balanced`; Tabelle `knowledge/model-tiers.md` | unbekannter Wert → `balanced` + Hinweis (nie `frontier`) |
| S0.4 | Arbeits-Repo fork-sicher (`origin`) + Auth | **a** | `gh repo view "$(git remote get-url origin)"`, `ensure-gh-auth.sh` | Auth-Fehler → harter Abbruch mit Klartext |
| S0.5 | Session-Rotation auflösen (Default 1 Story) | **a** | `--all`-Flag-Prüfung; Runner-Scope = immer Default (1 Story) | `--all` gesetzt → **nicht** Runner-Scope → an LLM-Orchestrator übergeben |
| S0.6 | Security-Frische-Nudge (>90 Tage) | **a** | Datum-Diff, reiner Hinweis | n/a (blockiert nie) |
| S0.7 | **Orchestrator-Lessons `flow.md` lesen + befolgen** | **c** | Prosa-Lessons sind LLM-Kontext; ein Bash-Runner kann Prosa nicht „befolgen" | s. Risiko-Note unten — Runner liest sie **nicht**; mechanisch relevante Lessons müssen in Skript/Tests kodifiziert sein |
| S0.8 | **Projekt-Memory `memory.md` lesen + als Kontext voranstellen** | **a** | Datei lesen, Inhalt als `PROJECT-MEMORY:`-Block dem Dispatch voranstellen (reines Text-Prepend) | Datei fehlt → kein Prepend, kein Fehler (bestehendes Verhalten) |

> **Risiko-Note S0.7 (bewusst, verbindlich).** Der Runner kann prosaische `flow.md`-Lessons nicht interpretieren. Zwei davon betreffen aber **mechanische** Standard-Pfad-Schritte (flow/L06 Flip-Fixer, flow/L07/L08 Claim/Feature-Branch) — diese sind **bereits** in `board-ship.sh` bzw. dem Claim-Protokoll kodifiziert und werden vom Runner via Skript getragen, nicht via Prosa. Neue, künftige `flow.md`-Lessons, die den Standard-Pfad betreffen, greifen im Runner-Pfad **nicht automatisch**. **Konsequenz (bindend):** Solange der Runner läuft, ist `flow.md` **nicht** die Durchsetzungsebene für den Standard-Pfad — die Durchsetzung liegt in `board-round.sh` + seinen Fixture-Tests. Der Retro-Harvest von `flow.md` (SKILL.md §0) bleibt unberührt (Lernquelle), aber eine mechanisch relevante neue Lesson muss beim nächsten Retro **ins Skript** wandern, nicht nur in die Prosa. Das ist eine Owner-Entscheidungsfrage (§9-Q4).

### 1.2 Item-Wahl + Schätzung (§1/§1a)

| # | Ermessensfall | Klasse | Mechanik / Trigger | Eskalations-Ausgang |
|---|---|---|---|---|
| S1.1 | Board frisch holen + `board next` | **a** | `git fetch origin $default_branch` → `board next` (JSON) | JSON nicht parsbar → Abbruch mit Klartext, **kein** Raten |
| S1.2 | Spec-Referenz + `implements`-ACs aus JSON ziehen | **a** | JSON-Feld `spec`/`implements` | Feld fehlt/leer → Abbruch (ohne Spec kein Dispatch) |
| S1.3 | **Empty-Drain-Diagnose** `board ready` + WAITING-Aggregat `[Pflicht #12]` | **a** | `board ready` (Klartext, token-frei), `WAITING …`-Zeilen melden | n/a (rein diagnostisch) |
| S1.4 | **Stale-Reclamation-Fallback** (`reclaimable:true`) `[Pflicht #13]` | **a** | `board next` liefert `reclaimable`-Flag; Übernahme via Standard-Claim (§2) | Flag mehrdeutig → wie fehlend behandeln (nächstes Item), nie fremd-schreiben ausser bewusster Reclamation |
| S1.5 | §1a Schätzfelder aus Story-YAML lesen (Konsument-Pfad) | **a** | `size_est`/`dispo_est`/`tok_est` lesen, übernehmen | fehlend → Fallback-Heuristik |
| S1.6 | §1a Fallback-Heuristik (`n_ac`+`n_comp`+`label_bump` → Grössenklasse) | **a** | deterministisches Zählen + fixe Schwellen-Tabelle | Zählung 0 → `size_est="M"`, `ep_est=null` (K3) |
| S1.7 | §1a estimator-Dispatch bei L/XL | **a** (Trigger) | mechanischer Trigger `size_est∈{L,XL}` → estimator-Subsession | estimator-JSON nicht parsbar → `dispo_est=null`, kein Loop-Abbruch (K3) |
| S1.8 | §1a Baseline-Lookup (S/M) | **a** | `baseline.json`-Lookup, feste Fallback-Kette | keine Datei → `ep_est=null` (erwartet) |

### 1.3 Claim-Lock (§2) + Metrik (§2b)

| # | Ermessensfall | Klasse | Mechanik / Trigger | Eskalations-Ausgang |
|---|---|---|---|---|
| S2.1 | **Claim-Lock-Protokoll** (Token, set, commit, push) `[story-claim-lock AC1–AC5/AC11]` | **a** | reine Bash/Git-Sequenz, atomare Push-Serialisierung; headless, kein Dienst | s. §4.3 (Race), §1.3-S1.4 |
| S2.2 | **Claim-Race** (Push abgelehnt) `[Pflicht #20]` | **a** | rebase-freier Re-Read via `git show origin/…:<pfad>`; AC2/AC3 des bestehenden Protokolls | Retry-Budget (3) erschöpft → sauberer Abbruch (AC13), Story bleibt `To Do` |
| S2.3 | **Stale-Reclamation / Geist-In-Progress** `[Pflicht #13]` | **a** | Eigentümerwechsel via eigenen Token, gleicher Push-Pfad | Reclamation-Kollision → Push-Atomarität entscheidet, Verlierer nimmt nächstes Item |
| S2.4 | Metrik-Touchpoints (dispatch/item append, dispo-Spiegel, token-collect) `[Pflicht #11 tangiert]` | **a** | deterministische Arithmetik, bestehende Skripte `metrics-append-*.sh` | Metrik-Fehler blockiert nie (K3), aber **sichtbar** gemeldet |
| S2.5 | Single-Writer-Invariante `[story-claim-lock AC12]` | **a** | Runner schreibt nur die eigene geclaimte Story-YAML + eigene Metrik | Fremd-Schreib-Versuch = Design-Fehler → in Fixture-Test abgedeckt |

### 1.4 Design-Freigabe-Gate (§2c)

| # | Ermessensfall | Klasse | Mechanik / Trigger | Eskalations-Ausgang |
|---|---|---|---|---|
| S2c.1 | **Bestandsschutz** (kein UI-Projekt ODER Story ohne Label `ui`) `[Pflicht #3]` | **a** | `profile.language`/`domains` + Story-Label prüfen → Abschnitt entfällt | n/a |
| S2c.2 | Gate-Prüfung: `docs/design.md` existiert + `owner_approved` gesetzt | **a** | Datei-Existenz + Frontmatter-Feld | fehlt/`null` → nicht freigegeben (Vertrag) |
| S2c.3 | Nicht freigegeben, **headless** → Blocked | **a** | `board set … Blocked --reason "Design-Freigabe ausstehend"` | n/a (definierter Blocked-Ausgang) |
| S2c.4 | Nicht freigegeben, **interaktiv** → designer-Vorschlag + Owner-Freigabe | **c** | designer-Dispatch (opus-Pinning) + `AskUserQuestion` | **ausserhalb Runner-Scope** — solche Story an LLM-Orchestrator; Runner fährt nur den headless-Block (S2c.3) |

### 1.5 Build-Loop (§3) + Test-Gate (§4)

| # | Ermessensfall | Klasse | Mechanik / Trigger | Eskalations-Ausgang |
|---|---|---|---|---|
| S3.1 | Dossier/Notes/Memory-Injektion (`--parent`) | **a** | Datei lesen → `FEATURE-DOSSIER:`/`FEATURE-NOTES:`/`PROJECT-MEMORY:`-Prepend | fehlt → kein Prepend (`--parent` selbst = out of scope, s. §0) |
| S3.2 | coder-Dispatch | **a** (Trigger) | Subsession mit Minimal-Kontrakt (§3) | Handoff fehlt/leer → als Fehl-Runde behandeln → §5-Eskalation |
| S3.3 | reviewer-Dispatch + **Review-Gate parsen** `[Pflicht via AC3]` | **b** | `grep -E '^Review-Gate:\s*(PASS\|CHANGES-REQUIRED)\s*$'` | **kein** eindeutiger Treffer / mehrdeutig → **leichtes LLM-Urteil (§5)**, nie raten (A1/AC7) |
| S3.4 | **DB-Trigger-Zweitreview durch `dba`** `[Pflicht #4]` | **a** | Trigger = Label `db` ODER `git diff` matcht fixe Import-Heuristik (Architektur-Spec §11) — **identische** Heuristik wie heute (kein Regressions-Delta, AC9) | Heuristik-Treffer unsicher? → Trigger ist deterministisch; Rest-Risiko (unvollständige Importliste) via Fixture-Test überwacht |
| S3.5 | dba-Dispatch + Gate parsen (beide Gates PASS Pflicht) | **b** | wie S3.3, plus UND-Verknüpfung beider Gates | wie S3.3 |
| S3.6 | **SPEC-LÜCKE-Eskalation** `[Pflicht #1]` | **a** (Routing) | Marker `SPEC-LÜCKE:` im Handoff → `board set … Blocked` | die **Klassifikation** „Lücke vs. Bug" trifft der **dispatchte Agent** (LLM, in der Subsession) — der Runner routet nur den Marker mechanisch |
| S3.7 | **Schleifenschutz N=3** `[Pflicht #2]` | **a** | harter Iterations-Zähler; N>3 → `board set … Blocked "Loop-Schutz N=3"` | Runner nutzt reinen Zähler-Cap (≥ heutige Garantie — „selber Befund"-Erkennung ist strenger nicht nötig, Zähler deckt es ab) |
| S4.1 | tester-Dispatch + **Test-Gate parsen** `[Pflicht via AC3]` | **b** | `grep -E '^Test-Gate:\s*(PASS\|FAIL\|SKIPPED-NO-DOCKER\|SKIPPED-DOC-ONLY\|SKIPPED-NO-BUILD)\s*$'` | mehrdeutig → **leichtes LLM-Urteil (§5)** |
| S4.2 | `SKIPPED-NO-DOCKER` → Human-Handoff `[Pflicht #14]` | **a** | Marker → `board set … Blocked "DB-Smoke ohne Docker"` | definierter Blocked-Ausgang, kein Bypass |
| S4.3 | `SKIPPED-DOC-ONLY` → äquiv. PASS | **a** | Marker → weiter zu Landen | n/a |
| S4.4 | **Template-Diff = hartes Test-Gate** `[Pflicht #14]` | **a** | `git diff --name-only` gegen Pflicht-Pfade (`templates/_shared/db-*/**` etc.) → PASS Pflicht | Pfad-Match unsicher? Pfad-Glob ist deterministisch; kein Bypass auch bei `direct` |

### 1.6 Landen (§5/§5a) + Abschluss (§6/§7)

| # | Ermessensfall | Klasse | Mechanik / Trigger | Eskalations-Ausgang |
|---|---|---|---|---|
| S5.1 | Landen via `board-ship.sh` (Modus A) | **a** | bestehendes Skript, unverändert (K1) | Exit≠0 → §4.1 Recover (Flip-Fixer), nicht blind „nicht gelandet" |
| S5.2 | **Flip-Fixer** (gelandet, Status-Flip fehlt, `flow/P3`) `[Pflicht #18]` | **a** | `gh pr list --head <branch> --state all`; MERGED → Restschritte mechanisch nachziehen | Remote-State nicht ermittelbar → `NEEDS-HUMAN` (fail-safe, §4.1) |
| S5.3 | **Claim-Releaser** (Story hängt `In Progress` nach Abbruch) `[Pflicht #19]` | **a** | Stale-Reclamation-Pfad (S2.3) beim nächsten Lauf; ODER Runner-eigener EXIT-Trap setzt verwaisten Claim zurück (s. §4.2) | Trap-Fehler → Story bleibt `In Progress`, wird beim nächsten `board next` als `reclaimable` erkannt (Netz) |
| S5.4 | **Rollout-Gate FAIL / NEEDS-HUMAN** `[Pflicht #10]` | **a** | `board-ship.sh`-Exit + Marker → `board set … Blocked` | definierter Blocked-Ausgang, Owner vorlegen |
| S5.5 | **Post-Rebase-Verifikation** (`flow/P2`) `[Pflicht #15]` | **b** | Standard-Runde: CI-Watch in `board-ship.sh` deckt es (a); **lokale Konfliktauflösung** braucht Urteil | Konflikt beim Landen → **out of standard-round scope** → an LLM-Orchestrator/cicd eskalieren |
| S5.6 | Handoff-Notiz schreiben (`--parent`, 3–5 Zeilen) `[via §5]` | **c** | Prosa-Zusammenfassung „was gebaut/was die nächste Story wissen muss" | `--parent` = out of scope (§0); im Runner-Scope entfällt der Schritt |
| S5.7 | **ID-Block-Freigabe (Solo-Pfad)** `[Pflicht #8]` | **a** | `board-id-reserve.sh release <story-id>`, idempotent | Fehlschlag nicht-fatal (Story gelandet), Klartext-Hinweis |
| S5.8 | **Validate-Flag-Invalidierung** (§5a) `[Pflicht #16]` | **a** | `yq`-Vergleich / Pfad-Match / Plugin-SHA — deterministische Trigger | kein Trigger → Flag unangetastet |
| S6.1 | **Session-Rotation** (Default 1 Story) `[Pflicht #17]` | **a** | Runner endet nach 1 Story; `--all` = out of scope | s. S0.5 |
| S6.2 | **Blocked-Ausgänge aller Art** `[Pflicht #9]` | **a** | jeder Blocked-Grund ist ein definierter Marker/Exit → `board set … Blocked` + Runde-Ende | Sammelknoten aller obigen Blocked-Zweige |
| S7.1 | **Projekt-Memory kuratieren** (§7) `[Pflicht #11]` | **c** | Neu-Schreiben/Kürzen von Prosa, Stale-Einträge streichen, ≤60 Zeilen | **leichter LLM-Kurations-Call am Runden-Ende** (§5) — der einzige *garantierte* LLM-Call einer sonst LLM-freien Standard-Runde; Owner-Frage §9-Q3 (Batchen/Aufschieben) |
| S7.2 | Board-Status-Ausgabe §7a | **a** | `board next` + `board ready --quiet`, Klartext | n/a |
| S7.3 | Abschluss-Deploy §7b (`deploy==docker`) | **a** | `board-ship.sh` deckt Rollout in §5; §7b nur Zusammenfassung. Für agent-flow (`deploy:none`) n/a | Best-effort, blockiert nie |

### 1.7 Parallelität/Planung — ausserhalb des Runner-Scopes (dokumentiert der Vollständigkeit halber, AC6-erschöpfend)

| # | Ermessensfall | Klasse | Anmerkung |
|---|---|---|---|
| P.1 | **SR1 Hot-Spot-Serialisierung + parallele Worktrees** `[Pflicht #5]` | **c** | Hot-Spot-Datei-Analyse = LLM-Urteil → nicht Runner-Scope; bleibt LLM-Orchestrator/§0a |
| P.2 | **Feature-Batch-Modus** (`--parent`) `[Pflicht #6]` | **c**/gemischt | Orchestrierung via `board-feature-drain.sh` (mechanisch) + Dossier-Erzeugung (LLM); Runner ist der **Story-Ebenen-Arm**, den der Drain künftig statt `claude -p /flow` rufen könnte (s. §7) |
| P.3 | **Wellen-Plan-Revalidierung** (`--plan`/§0b/§0c) `[Pflicht #7]` | Plan=**c**, Revalidierung=**a** | Planbildung LLM (einmalig); Revalidierung bereits mechanisch (`board-plan-validate.sh`) |

**Bilanz.** Die board-weite Standard-Einzelrunde ist **vollständig (a)**, mit **(b)**-Eskalation an genau drei Textmuster-Stellen (Review-Gate, Test-Gate, dba-Gate) und **genau einem** garantierten (c)-Call am Runden-Ende (Memory-Kuration). Alle übrigen (c)-Fälle liegen in ausgeschlossenen Domänen (--all/--parent/--plan/SR1/Design-interaktiv) und lösen den Runner gar nicht erst aus.

---

## 2. Zustandsautomat des Runden-Runners

`scripts/board-round.sh` — eine Runde, ein Item, dann Exit (Session-Rotation-Default). Zustände, Übergänge, auslösendes Skript/Textmuster.

```
        ┌─────────┐
        │  SETUP  │  S0.* — profile/auth/cost-mode/rotation/memory-read
        └────┬────┘
             │ ok
        ┌────▼────┐
        │ SELECT  │  git fetch; board next
        └────┬────┘
     item │  │ leer
          │  └────────────► DIAGNOSE ──► FINALIZE (Empty-Drain, S1.3)
          ▼
        ┌─────────┐
        │  CLAIM  │  Claim-Protokoll (S2.*)
        └────┬────┘
   push ok │  │ Re-Read: fremd-frisch (AC3)      ──► SELECT (nächstes Item)
           │  │ Re-Read: noch To Do (AC4)         ──► CLAIM (Retry, Budget 3)
           │  │ Budget erschöpft (AC13)           ──► FINALIZE (Abbruch, To Do)
           ▼
        ┌────────────┐
        │ DESIGN_GATE│  nur UI+Label ui (S2c.*)
        └────┬───────┘
   pass │    │ nicht freigegeben, headless ──► BLOCK("Design-Freigabe ausstehend")
        │    │ interaktiv                   ──► HANDOFF_LLM (out of scope)
        ▼
   ┌──────────────────────  BUILD-LOOP (N=1..3)  ──────────────────────┐
   │  ┌────────┐                                                        │
   │  │  CODE  │  coder-Dispatch (§3, Minimal-Kontrakt)                 │
   │  └───┬────┘                                                        │
   │      │ Done            │ SPEC-LÜCKE-Marker ──► BLOCK               │
   │      ▼                                                             │
   │  ┌────────┐                                                        │
   │  │ REVIEW │  reviewer-Dispatch; parse Review-Gate                  │
   │  └───┬────┘                                                        │
   │      │ PASS         │ CHANGES-REQUIRED ──► ITERATE(N++)            │
   │      │              │ Muster mehrdeutig ──► JUDGE(§5) ──► (PASS|CR)│
   │      ▼                                                             │
   │  ┌──────────┐  DB-Trigger? (S3.4)                                  │
   │  │ DB_REVIEW│  ja: dba-Dispatch; beide Gates PASS Pflicht         │
   │  └───┬──────┘  nein: skip                                         │
   │      │ PASS (beide)  │ CHANGES-REQUIRED ──► ITERATE(N++)          │
   │      ▼                                                             │
   │  ┌────────┐                                                        │
   │  │  TEST  │  tester-Dispatch; parse Test-Gate                      │
   │  └───┬────┘                                                        │
   │      │ PASS / SKIPPED-DOC-ONLY                                     │
   │      │ FAIL ──► ITERATE(N++)                                       │
   │      │ SKIPPED-NO-DOCKER ──► BLOCK                                 │
   │      │ Muster mehrdeutig ──► JUDGE(§5)                             │
   │      │                                                             │
   │   ITERATE: N++ ; wenn N>3 ──► BLOCK("Loop-Schutz N=3") ; sonst CODE│
   └──────┬─────────────────────────────────────────────────────────────┘
          ▼ beidseitig PASS
        ┌────────┐
        │  LAND  │  board-ship.sh <story-id>  (Modus A)
        └───┬────┘
   exit 0 │  │ exit ≠ 0 ──► RECOVER
          │  ▼
          │ ┌─────────┐  Flip-Fixer (S5.2): gh pr list MERGED?
          │ │ RECOVER │  ja  ──► Restschritte nachziehen ──► (Done)
          │ └────┬────┘  nein/unklar ──► BLOCK(NEEDS-HUMAN)
          ▼      ▼
        ┌──────────┐
        │ FINALIZE │  metrics item + token-collect + dispo-mirror;
        │          │  ID-release; Memory-Kuration (JUDGE-Kanal §5, S7.1);
        │          │  §7a Board-Status; Session-Ende-Commit
        └────┬─────┘
             ▼
           EXIT (Rotation-Default: eine Story, dann Ende)
```

**Kanten mit Auslöser (verbindliche Übergangstabelle):**

| Von → Nach | Auslöser (Skript / Textmuster) |
|---|---|
| SETUP → SELECT | S0.* alle ok |
| SELECT → CLAIM | `board next` liefert Item-JSON mit `id`+`spec` |
| SELECT → DIAGNOSE | `board next` leer → `board ready` |
| DIAGNOSE → FINALIZE | immer (Runde endet, Exit 0) |
| CLAIM → DESIGN_GATE | Claim-Push fast-forward bestätigt |
| CLAIM → SELECT | Re-Read: `status=In Progress` + fremder frischer `claimed_by` (AC3) |
| CLAIM → CLAIM | Re-Read: `status=To Do`, Retry-Budget < 3 (AC4) |
| CLAIM → FINALIZE | Retry-Budget erschöpft (AC13) → `To Do`, Klartext-Abbruch |
| DESIGN_GATE → CODE | Bestandsschutz greift **oder** Gate erfüllt |
| DESIGN_GATE → BLOCK | UI+`ui`, nicht freigegeben, headless |
| CODE → REVIEW | coder-Handoff enthält `Review-Handoff: REVIEW REQUIRED` |
| CODE → BLOCK | coder-Handoff enthält `SPEC-LÜCKE:` |
| REVIEW → DB_REVIEW / TEST | `Review-Gate: PASS` (DB-Trigger entscheidet Zwischenschritt) |
| REVIEW → CODE (ITERATE) | `Review-Gate: CHANGES-REQUIRED` |
| REVIEW → JUDGE | Gate-Zeile fehlt / mehrdeutig / mehrfach |
| DB_REVIEW → TEST | `Review-Gate: PASS` (dba) UND reviewer-PASS |
| DB_REVIEW → CODE (ITERATE) | dba `Review-Gate: CHANGES-REQUIRED` |
| TEST → LAND | `Test-Gate: PASS` \| `SKIPPED-DOC-ONLY` |
| TEST → CODE (ITERATE) | `Test-Gate: FAIL` |
| TEST → BLOCK | `Test-Gate: SKIPPED-NO-DOCKER` |
| TEST → JUDGE | Gate-Zeile mehrdeutig |
| ITERATE → CODE | N++ und N ≤ 3 |
| ITERATE → BLOCK | N > 3 (`Loop-Schutz N=3`) |
| LAND → FINALIZE | `board-ship.sh` Exit 0 |
| LAND → RECOVER | `board-ship.sh` Exit ≠ 0 |
| RECOVER → FINALIZE | `gh pr list … state=MERGED` → Flip nachgezogen (Done) |
| RECOVER → BLOCK | Remote-State ≠ MERGED oder nicht ermittelbar → NEEDS-HUMAN |
| JUDGE → (Ursprungszustand) | leichter LLM-Judge liefert normalisiertes Gate-Token (§5) |
| JUDGE → BLOCK | Judge liefert „AMBIGUOUS"/Fehler → Owner (§5) |
| BLOCK → FINALIZE | `board set … Blocked --reason …` gesetzt |
| FINALIZE → EXIT | Rotation-Default (1 Story) |

**Invarianten (Fixture-Test-Pflicht, analog `tests/board-ship/`):**
- I1 — Aus **jedem** Zustand ist genau ein Blocked-/Abbruch-Ausgang erreichbar (kein stiller Hang). Sicherheitsnetz analog `board-feature-drain.sh` „unklarer Zustand → Exit 3 mit Diagnose".
- I2 — Board-Status wird **nur** in CLAIM (In Progress), BLOCK (Blocked), LAND/RECOVER (Done via `board-ship.sh`) geschrieben — Single-Writer `/flow`-Pfad bleibt (AC11).
- I3 — Kein `coder`-Dispatch vor bestätigtem Claim-Push (CLAIM strikt vor CODE) — story-claim-lock AC1.
- I4 — EXIT-Trap: bricht der Runner-Prozess selbst ab (Timeout/toter Kontext), setzt ein Trap den aktuellen Zustand in ein Runner-State-File (analog `board/runs/<F>/state.yaml`) und den verwaisten Claim in einen reclaimable-fähigen Zustand (§4.2).

---

## 3. Minimal-Kontext-Verträge je Rolle (AC2)

**Prinzip.** Jeder Agent-Dispatch ist eine **eigene headless `claude -p`-Subsession** (bzw. äquivalenter isolierter Subagent-Aufruf, Mechanik owner-offen §9-Q1). Der Runner übergibt **nur** den unten definierten Minimal-Kontrakt. Die Agenten **laden ihren restlichen Kontext selbst** (das ist bereits so entworfen — jede Agent-Datei hat einen „Zuerst lesen"-Block, der Spec/Profile/Packs/Lessons zieht). Der Gewinn ist **nicht**, den Agenten Kontext zu entziehen, sondern dass **kein grosser Orchestrator-Kontext** (SKILL.md + wachsender Verlauf) je Werkzeug-Schritt neu gelesen wird und jede Subsession bei fixem, kleinem Prompt startet.

**Bekommt JEDER Dispatch (gemeinsamer Kern):**
- `ROLE` (coder|reviewer|tester|dba|estimator)
- `STORY: S-###` (der Agent liest Details via `board show <story-id>` selbst — nicht der Runner)
- `SPEC: docs/specs/<feature>.md (AC<…>)` (aus dem `board next`-JSON, Source of Truth)
- `MODEL-OVERRIDE` gemäss Cost-Mode (S0.3) — bzw. keiner bei `balanced`
- `BASE_SHA` (bei Claim gemerkt; Referenz für `git diff`/shortstat)

**Bekommt NIEMAND mehr (bewusst entzogen ggü. heute):**
- die vollständige `skills/flow/SKILL.md`
- der kumulierte Gesprächsverlauf der Runde / vorheriger Agenten (jeder Agent sieht nur den Working-Tree + seinen Kontrakt)
- der `--plan`-Wellenplan, andere Stories, der `§0a`-Abarbeitungsplan

**Rollenspezifische Ergänzung:**

| Rolle | Zusätzlich im Kontrakt | Selbst-geladen (nicht vom Runner) |
|---|---|---|
| coder | `ITERATION: N`; bei N>1 `FINDINGS:` (Critical+Important aus letztem Review, wörtlich durchgereicht) | Spec, profile, CLAUDE.md, `coder.md`-Lessons, Sprach-/Framework-Packs, `architecture/data-model/design.md`, betroffener Code |
| reviewer | — (liest `git diff` gegen `BASE_SHA` selbst im Worktree) | Diff, Spec, `coder.md`+`reviewer.md`-Lessons, Packs, Security-Floor |
| dba | Item-Label (`db`) als Hinweis; Review-Modus | Diff, Spec, DB-Packs |
| tester | — (fährt Build/Test/Lint/Smoke selbst gegen den Working-Tree) | profile-Befehle, Spec, `coder.md`+`tester.md`-Lessons, Test-Approach-Packs |
| estimator | `SIZE_EST`, `COST_MODE` | Story-YAML, Spec, `reference-stories.md`, `baseline.json`, `items.jsonl` |

**Bei `--parent` (out of first scope, aber Kontrakt vorbereitet):** zusätzlich vorangestellt `FEATURE-DOSSIER:`/`FEATURE-NOTES:`/`PROJECT-MEMORY:`-Blöcke (reines Text-Prepend, S3.1).

**Handoff-Rückkanal (unverändert zu heute — AC3):** Der Runner liest aus dem Klartext-Handoff der Subsession **ausschliesslich** die definierten Marker:
- coder: `Done:` / `Review-Handoff: REVIEW REQUIRED (#…, Iteration N)` / `Spec: … SPEC-LÜCKE: …`
- reviewer/dba: `Review-Gate: PASS | CHANGES-REQUIRED` + `## Critical`/`## Important`-Zähler (für Metrik)
- tester: `Test-Gate: PASS | FAIL | SKIPPED-NO-DOCKER | SKIPPED-DOC-ONLY | SKIPPED-NO-BUILD`
- estimator: JSON-Objekt (`dispo_est`/`tok_est`/…)

Der Runner **parst nur diese Marker** — er interpretiert den Fliesstext nicht. Fehlt/mehrdeutig → §5.

---

## 4. Fehlerpfade (AC8 — mindestens so stark wie die heutigen manuellen Workarounds)

Die drei real beobachteten Abbruch-Fehlerklassen. Jede wird **strukturell** abgefangen, nicht schwächer als der heutige Bash-Workaround.

### 4.1 Flip-Fixer — gelandet, aber Board-Flip fehlt (E1/AC8, `flow/P3`, `flow/L06`)

**Symptom.** Session endete während der CI-Beobachtung im Landen-Schritt; der Code ist remote bereits gemergt, aber die Story steht noch `In Review`/`In Progress` ohne `Done`-Stempel.

**Strukturelle Abfangung.** Zwei ineinandergreifende Ebenen:
1. **`board-ship.sh` ist bereits idempotent** (Schritt 1: `merge-base --is-ancestor` + squash-tauglicher `pr_head_branch_merged`-Check). Ein erneuter Aufruf auf eine bereits gemergte Story erkennt das (`ALREADY_MERGED=1`) und zieht **nur** die Restschritte nach (CI-Check/Board-Flip im temporären detached Worktree). Der Runner ruft `board-ship.sh` also gefahrlos erneut.
2. **RECOVER-Zustand** im Runner: Bricht `board-ship.sh` mit Exit≠0 ab (z. B. `flow/P3`: Zielbranch in anderem Worktree belegt), behandelt der Runner das **nicht** automatisch als „nicht gelandet". Er prüft zuerst den Remote-State — `gh pr list --head <branch> --state all --json state,mergedAt`:
   - `MERGED` → Landung ist erfolgt → Restschritte mechanisch nachziehen (frischer detached Checkout auf `origin/$default_branch`, `board set … Done` + `pr` + dispo-Mirror, Commit, Push) → FINALIZE(Done).
   - **nicht** MERGED / Abfrage gescheitert → `NEEDS-HUMAN` (fail-safe, K1) — **nie** blinder Retry, **nie** stilles „gescheitert".

Das ist **exakt** der manuelle `flow/L06`-Workaround, in den Zustandsautomaten gehoben. Prävention (SR1): Story-Worktree erst **nach** bestätigter Landung abbauen.

### 4.2 Claim-Releaser — Story hängt `In Progress` nach Abbruch (E1/AC8)

**Symptom.** Session endete mitten im Review-Loop; die Story bleibt dauerhaft `In Progress` mit dem Claim einer toten Session.

**Strukturelle Abfangung.** Zwei Netze:
1. **EXIT-Trap im Runner (Invariante I4, primär).** Analog `board-feature-drain.sh` `on_error_state`: Bei jedem nicht-erfolgreichen Prozess-Ende schreibt ein Trap den Runner-Zustand in ein State-File und **verwaisten Claim** nicht neu — sondern belässt ihn bewusst als `In Progress` mit dem (nun toten) `claimed_by`/`claimed_at`. Wichtig: der Runner setzt **nicht** aggressiv auf `To Do` zurück, weil ein noch lebender Parallel-Prozess denselben Claim halten könnte (Fremd-Schreib-Verbot AC12).
2. **Stale-Reclamation-Netz (sekundär, zeitbasiert).** Der bestehende `story-claim-lock`-Pfad (AC7/AC8): nach `stale_claim_hours` (Default 4h) liefert `board next` die Story als `reclaimable:true`, und der nächste Runner-Lauf übernimmt sie über den **normalen** Claim-Ablauf (Eigentümerwechsel, S2.3). Kein manueller Eingriff, kein Dauer-Block.

**Verhältnis zu `board-feature-drain.sh`.** Dessen `orphaned_story_ids()` setzt liegengebliebene Stories **sofort** auf `To Do` zurück — das ist im **Feature-Scope** sicher (der Drain ist der einzige Schreiber des Feature-Branches). Board-weit ist die zeitbasierte Stale-TTL der korrekte, race-sichere Mechanismus (mehrere parallele Sessions möglich). Der Runner nutzt board-weit **die TTL**, nicht das sofortige Zurücksetzen — bewusst konservativer als der Feature-Drain, weil der Blast-Radius grösser ist.

### 4.3 Claim-Race — konkurrierende Parallel-Sessions (E2/AC4, `[Pflicht #20]`)

**Strukturelle Abfangung — kein Neubau.** Der Runner **nutzt** das bestehende Push-basierte Claim-Protokoll aus S-120 (`story-claim-lock` AC2/AC3, `skills/flow/SKILL.md` §2) unverändert:
- Push abgelehnt → **rebase-frei** (nie `git rebase`/`git merge` — Story-YAML-Konflikt praktisch garantiert, hängender Rebase-Zustand). Re-Read via `git show origin/$default_branch:<pfad>` (Working-Tree unangetastet).
- fremd+frisch → eigene Reservierung verwerfen (`git reset --hard`), nächstes Item (AC3).
- noch `To Do` → Retry (gleicher Token), Budget 3 (AC4).
- Budget erschöpft → sauberer Abbruch, Story bleibt `To Do` (AC13).

**Verbindlich:** Der Runner **erfindet kein neues Lock-/Race-Protokoll** (AC4, Spec-Nicht-Ziel). Er ruft die bereits in `scripts/board` + dem Claim-Ablauf lebende Mechanik.

---

## 5. Eskalations-Mechanik (A1/A2, AC7 — nie stillschweigend raten)

Zwei Eskalations-Kanäle, beide **fokussiert** (kein grosser Orchestrator-Kontext).

### 5.1 Leichtes LLM-Urteil (Judge) — mehrdeutiger Gate-Text (A1)

**Auslöser.** Ein Gate-Parse (S3.3/S3.5/S4.1) matcht das erwartete Regex **nicht eindeutig**: keine Zeile, mehrere widersprüchliche Zeilen, oder ein unbekanntes Token (z. B. ein neuer `SKIPPED-*`-Wert, ein Tippfehler, Gate-Zeile in Prosa eingebettet).

**Mechanik.**
1. Der Runner startet einen **eng umrissenen** `claude -p`-Judge-Call. Kontext: **ausschliesslich** der Handoff-Text des betreffenden Agenten + die feste Frage: *„Welches Gate-Token trifft zu? Antworte mit **genau einem** von: `PASS` | `CHANGES-REQUIRED` | `FAIL` | `SKIPPED-NO-DOCKER` | `SKIPPED-DOC-ONLY` | `SKIPPED-NO-BUILD` | `AMBIGUOUS`. Keine Begründung."* (rollenabhängige erlaubte Menge).
2. Modell: günstigste sinnvolle Stufe (`knowledge/model-tiers.md`; Judge ist ein Klassifikations-Mini-Call, kein Design) — Owner-Frage §9-Q2.
3. Rückgabe ein bekanntes Token → Runner fährt den entsprechenden Übergang (§2) wie beim direkten Match.
4. Rückgabe `AMBIGUOUS` (oder Judge-Fehler/Timeout/leer) → **kein Weiterraten** → Owner-Eskalation: `board set … Blocked --reason "Gate-Text uneindeutig — manuelle Klärung nötig"` + Klartext-Meldung. Runde endet über BLOCK→FINALIZE.

**Warum ein Judge und kein grösserer Kontext.** Der Judge sieht nur den einen Handoff — er ersetzt nicht den Orchestrator, er normalisiert nur ein Token. Kosten ~ ein Mini-Call, nicht eine Runde.

### 5.2 LLM-Kurations-Call — Memory (S7.1, garantierter (c)-Call)

Am Runden-Ende (FINALIZE) ruft der Runner einen fokussierten `claude -p`-Kurations-Call (Kontext: bestehendes `.claude/memory.md` + Kurz-Handoff-Ergebnis dieser Story + das Template-Gerüst) für den §7-Memory-Schritt. Dies ist der **einzige zwingende** LLM-Call einer sonst LLM-freien Standard-Runde. Owner-Frage §9-Q3: pro Runde vs. gebatcht am Aussenschleifen-Ende.

### 5.3 Owner-Eskalation — echter Ermessensfall (A2)

Fälle, die per Konstruktion **nicht** in den Runner-Scope fallen (Klasse (c) ausserhalb Standard-Runde: interaktive Design-Freigabe, lokale Rebase-Konfliktauflösung, SR1-Parallel-Planung), erkennt der Runner **an einem definierten Vorab-Filter** (SETUP prüft: `--all`/`--parent`/`--plan`-Flag, UI+`ui`-ohne-Freigabe-interaktiv, Landen-Konflikt) und **gibt an den LLM-Orchestrator ab** (bzw. bricht mit Klartext ab, wenn headless kein Owner erreichbar). Der Runner **entscheidet solche Fälle nie selbst**.

---

## 6. Bewertung Stufe 1 & Stufe 2

### 6.1 Stufe 1 (Mechanik-Bündelung) — **Vorstufe, wird absorbiert, nicht obsolet**

Stufe 1 bündelt die **Claim-Sequenz** (Token/set/commit/push) und die **Abschluss-Sequenz** (Metrik-Writes, Dispo-Spiegel, Memory-/Board-Meta-Commit) in je ein deterministisches Skript — analog `board-ship.sh`.

**Bewertung.** Diese Skripte sind **exakt die mechanischen Primitive**, aus denen der Runner die Zustände CLAIM und FINALIZE zusammensetzt. Der Runner **erfindet sie nicht neu**, er ruft sie:
- CLAIM ⇒ `scripts/board-claim.sh <story-id>` (Stufe-1-Claim-Skript).
- FINALIZE ⇒ `scripts/board-round-finalize.sh <story-id>` (Stufe-1-Abschluss-Skript) — Metrik-Append + token-collect + dispo-Mirror + ID-release + Board-Meta-Commit. (Der Memory-Kurations-**Call** bleibt LLM, §5.2 — das Skript committet nur das Ergebnis.)

**Empfehlung.** Stufe 1 **zuerst** umsetzen, als **eigenständige, fixture-getestete Stories** (Muster `tests/board-ship/`). Sie sind risikoarm (kein Verhaltensdelta, nur weniger Werkzeug-Aufrufe), liefern **sofort** Wert im heutigen LLM-Orchestrator (weniger Tool-Calls je Runde) **und** werden zu den geprüften Bausteinen des Runners. Kein Doppel-Bau. → Stufe 1 ist **nicht obsolet**; sie ist die verifizierte Fundament-Schicht (ADR-1).

### 6.2 Stufe 2 (SKILL.md-Zerlegung Kern + Bei-Bedarf-Kapitel) — **unabhängig komplementär, ROI sinkt nach Stufe 3**

Stufe 2 zerlegt `SKILL.md` in einen schlanken Kern + Sonderfall-Kapitel (Lazy-Loading).

**Bewertung.** Stufe 2 senkt den Fix-Kontext **des LLM-Orchestrators**. Nach Stufe 3 liest der Orchestrator die `SKILL.md` in der **Standard-Runde gar nicht mehr** (Bash-Runner) — dort greift Stufe 2 also nicht. Stufe 2 hilft weiterhin für: (a) die **verbliebenen** LLM-Pfade (Eskalation §5.3, `--all`/`--parent`/`--plan`/Design-interaktiv); (b) als **Struktur-Quelle** für die Runner-Dispatch-Kontrakte (der „Kern" ist genau das, was der Runner mechanisiert — die Zerlegung macht die Grenze zwischen mechanisch und Ermessen explizit lesbar).

**Empfehlung.** Stufe 2 bleibt **sinnvoll, aber nachrangig** zum Runner selbst. Zwei Optionen für den Owner (§9-Q5): (i) Stufe 2 als eigene, kleine Aufräum-Story **nach** dem Runner (die Kern/Kapitel-Grenze fällt dann mit der (a)/(c)-Klassifikation aus §1 zusammen); (ii) Stufe 2 ganz aufschieben, falls die verbliebenen LLM-Pfade selten genug sind, dass ihr Kontext-Gewicht nicht mehr ins Gewicht fällt. → Stufe 2 wird durch Stufe 3 **nicht obsolet**, aber ihr Einspar-ROI schrumpft; sie ist eine **unabhängige** Verbesserung, kein Blocker für den Runner (ADR-2).

**Reihenfolge-Empfehlung gesamt:** Stufe 1 (Primitive + Tests) → Runner (Stufe 3, dogfood) → optional Stufe 2 (Aufräumen des Rest-LLM-Pfads).

---

## 7. Migrations-Empfehlung — **schrittweise, dogfood-first, KEIN Big-Bang**

**Begründung (S-047-Doktrin).** Ein Fehler dieser Feature ist **unsichtbar** (falsch gelandete/übergangene Story). Ein Big-Bang-Umschalten des Standard-Pfads auf einen ungetesteten Bash-Automaten widerspricht der Doktrin frontal. Genau deshalb übernahm `board-ship.sh` historisch **nur** den mechanischsten Schritt und wuchs testfixture-gedeckt. Der Runner folgt demselben Pfad.

**Warum „echter Shadow-Mode" (beide bauen dieselbe Story parallel, Vergleich) nicht geht.** `main`/das Board ist **eine** serielle Senke, und eine Story kann nur **einmal** gebaut/gelandet werden. Zwei Builder auf dieselbe Story = Race, kein sauberer Vergleich. Der „Shadow" muss deshalb über **Decision-Trace + gestaffelte Freigabe** laufen, nicht über Doppel-Bau.

**Empfohlene Phasen:**

- **Phase A — Primitive härten (Stufe 1).** `board-claim.sh` + `board-round-finalize.sh` + ein reiner **Gate-Parser** (`scripts/parse-gate.sh`, Regex + Exit-Codes) als eigenständige, **fixture-getestete** Skripte (`tests/board-round/`). Kein Verhaltensdelta. Sofort im heutigen Orchestrator nutzbar.
- **Phase B — Runner opt-in, dogfood.** `scripts/board-round.sh` hinter einem **expliziten** Einstieg (`/flow --runner` oder ein separater Skript-Aufruf durch die Aussenschleife) — **nur** auf dem agent-flow-Selbst-Board (`board:5`, `merge_policy:pr`, `deploy:none` → kleiner Blast-Radius, kein Docker-Rollout im Spiel). Der LLM-Orchestrator bleibt Default für alle anderen Projekte.
- **Phase C — Decision-Trace + Audit.** Der Runner schreibt je Zustandsübergang eine **Trace-Zeile** (`board/runs/round-<story>.trace`, gitignored): welcher Zustand, welches Gate-Token, welcher Auslöser, welche Eskalation. Der Owner (oder ein Retro-Lauf) prüft die Traces mehrerer Dogfood-Runden gegen die erwartete Semantik. Jede Diskrepanz (falsch geparste Gate-Zeile, unnötige Eskalation, verpasster Blocked-Ausgang) ist eine Korrektur an Parser/Zustandsautomat **vor** breiterer Freigabe. Das ist der praktikable „Shadow": nicht Doppel-Bau, sondern **beobachtbarer, auditierbarer** Runner-Lauf mit LLM-Orchestrator als jederzeit-Rückfallebene.
- **Phase D — Default-Flip für Standard-Runden.** Erst nach N sauberen Dogfood-Runden (Owner-Schwelle) wird der Runner Default für die **board-weite Standard-Einzelrunde**; der LLM-Orchestrator wird nur noch bei Eskalation (§5.3) / ausserhalb des Scopes gerufen. `--all`/`--parent`/`--plan`/SR1/Design-interaktiv bleiben LLM.
- **Phase E (optional, später) — Feature-Batch integrieren.** `board-feature-drain.sh` könnte künftig pro Story `board-round.sh --parent F-###` statt `claude -p /flow --parent` rufen — dann greift die Stufe-3-Ersparnis auch im Feature-Batch. Separater Entwurf, nicht Teil des ersten Schnitts.

**Rückfall-Garantie (verbindlich).** In jeder Phase ist der LLM-Orchestrator ein Ein-Flag-Rückfall. Der Runner ist **additiv**, nie ein Ersatz, der den alten Pfad entfernt, bevor Phase D bestätigt ist.

---

## 8. Skript-Schnitt (bindende Komponenten-Grenzen für den coder)

| Komponente | Verantwortung | Wiederverwendet / neu |
|---|---|---|
| `scripts/board-round.sh` | Zustandsautomat (§2), einzige Runden-Steuerung, hält keinen LLM-Kontext | **neu** (Stufe 3) |
| `scripts/board-claim.sh` | CLAIM-Sequenz (S2.1–S2.3), rebase-frei, Retry-Budget | **neu** (Stufe 1) |
| `scripts/board-round-finalize.sh` | FINALIZE-Mechanik: Metrik-Append + token-collect + dispo-Mirror + ID-release + Board-Meta-Commit | **neu** (Stufe 1) |
| `scripts/parse-gate.sh` | Gate-Token aus Handoff-Text (Regex, Exit-Codes: 0=eindeutig, 2=mehrdeutig→JUDGE) | **neu** (Stufe 1) |
| `scripts/board-ship.sh` | LAND + Flip-Fixer-Idempotenz (§4.1) | **wiederverwendet, unverändert** (K1) |
| `scripts/board` (`next`/`ready`/`set`) | Item-Wahl, Diagnose, Status-Schreiben | **wiederverwendet** |
| `scripts/board-id-reserve.sh` | ID-Block release (S5.7) | **wiederverwendet** |
| `scripts/metrics-*.sh` | Ledger-Touchpoints (S2.4) | **wiederverwendet** |
| Agent-Subsession-Dispatch | `coder`/`reviewer`/`tester`/`dba`/`estimator` als `claude -p` mit Minimal-Kontrakt (§3) | **neu (Mechanik owner-offen, §9-Q1)** |
| JUDGE-/Memory-`claude -p` | §5.1 / §5.2 fokussierte Mini-Calls | **neu** |

**Grenze (HART, Drift-Gate-prüfbar):**
- `board-round.sh` schreibt Board-Status **nur** über die bestehenden Wege (`board set` in CLAIM/BLOCK, `board-ship.sh` in LAND) — Single-Writer bleibt (AC11, I2).
- Kein neues Claim-/Race-/Lock-Protokoll (AC4) — `board-claim.sh` kapselt das **bestehende** S-120-Protokoll, ändert seine Semantik nicht.
- Jeder mechanisierte (a)-Schritt aus §1 hat im Skript einen **expliziten** Nicht-Match-Ausgang (Abbruch/Eskalation) — kein `|| true`-Verschlucken einer **Entscheidungs**-Frage (im Unterschied zu Metrik-`|| true`, das eine Nebensache ist, K3).
- Fixture-Tests (`tests/board-round/`) decken: jeden Zustandsübergang (§2-Tabelle), jeden Fehlerpfad (§4), die Invarianten I1–I4.

---

## 9. Offene Entscheidungsfragen für den Owner

> Nicht vom architekt entschieden — bewusst dem Owner vorgelegt. Format: frage / optionen / quelle.
> **Alle 7 Fragen vom Owner am 28.07.2026 entschieden** — durchgehend die architekt-Empfehlung (Option a). Entscheid je Frage direkt darunter vermerkt.

**Q1 — Dispatch-Mechanik der Agent-Subsessions.**
- frage: Wie werden `coder`/`reviewer`/`tester` vom Bash-Runner als isolierte Sessions gestartet?
- optionen: (a) `claude -p "<prompt>"` je Agent, exakt wie `board-feature-drain.sh` es auf Story-Ebene tut (bewährt, aber `-p` startet eine generische Session — die Agent-Rolle/Frontmatter muss im Prompt referenziert werden); (b) ein dünner LLM-Shell-Schritt, der nur das Task-Tool je Agent aufruft und sofort endet (näher an heute, aber hält kurz einen kleinen LLM-Kontext); (c) ein noch zu klärender direkter Subagent-Invoke ohne generische Session.
- quelle: `board-feature-drain.sh` Zeile 587 (`claude -p /flow --parent`); AC2; die Agent-Frontmatter (`name:`/`model:`) definiert die Rolle heute nur im Task-Tool-Kontext.
- **Entscheid (Owner, 28.07.2026): (a)** — `claude -p "<prompt>"` je Agent, analog `board-feature-drain.sh`. Bewährtes Muster, kein Neuland.

**Q2 — Modellstufe des Gate-Judge (§5.1).**
- frage: Auf welcher Cost-/Modell-Stufe läuft der leichte Gate-Normalisierungs-Call?
- optionen: (a) fix günstigste Stufe (Mini-Modell, unabhängig vom Runden-Cost-Mode); (b) an den aktiven Cost-Mode gekoppelt; (c) `haiku`-artig fix mit Owner-Override.
- quelle: `knowledge/model-tiers.md`; Judge ist ein Ein-Token-Klassifikations-Call.
- **Entscheid (Owner, 28.07.2026): (a)** — fix günstigste Modell-Stufe, unabhängig vom Cost-Mode der Runde. Die Klassifikationsfrage ist immer gleich trivial.

**Q3 — Memory-Kuration: pro Runde vs. gebatcht (§5.2, S7.1).**
- frage: Der einzige garantierte (c)-Call der Standard-Runde ist die §7-Memory-Kuration. Pro Runde ausführen (heutiges Verhalten, ein LLM-Call/Runde) oder gebatcht am Ende der Aussenschleife (spart Calls, weicht aber von SKILL.md §7 „letzter Schritt jeder Session" ab)?
- optionen: (a) pro Runde (verhaltensgleich zu heute, AC9-konform); (b) gebatcht am Aussenschleifen-Ende (Kosten-Ersparnis, erfordert Spec-Präzisierung `project-memory.md` AC3); (c) headless-Runden schreiben nur einen mechanischen `## Letzte Arbeiten`-Einzeiler (kein LLM), volle Kuration nur interaktiv.
- quelle: `skills/flow/SKILL.md` §7; `docs/specs/project-memory.md` AC3–AC6.
- **Entscheid (Owner, 28.07.2026): (a)** — pro Runde, verhaltensgleich zu heute. Keine Spec-Präzisierung nötig.

**Q4 — `flow.md`-Orchestrator-Lessons im Runner-Pfad (S0.7-Risiko).**
- frage: Der Bash-Runner kann prosaische `flow.md`-Lessons nicht „befolgen". Wie wird sichergestellt, dass eine künftige standard-pfad-relevante Lesson greift?
- optionen: (a) Retro-Konvention: standard-pfad-relevante `flow.md`-Lessons müssen bei Promotion **ins Skript/in einen Fixture-Test** wandern (Prosa bleibt nur Lernquelle); (b) der Runner liest `flow.md` **doch** einmalig und leitet daraus einen strukturierten Vorab-Check ab (bricht die „kein LLM-Kontext"-Reinheit); (c) Status quo akzeptieren + im Runner-Doc dokumentieren, dass `flow.md` für den Runner-Pfad nicht durchsetzend ist.
- quelle: `skills/flow/SKILL.md` §0 (flow.md-Vertrag); §1.1-S0.7 dieses Dokuments.
- **Entscheid (Owner, 28.07.2026): (a)** — Retro-Konvention: standard-pfad-relevante `flow.md`-Lessons wandern bei Promotion ins Skript/in einen Fixture-Test. Prosa bleibt Lernquelle, wird aber nicht mehr Durchsetzungsebene des Standard-Pfads.

**Q5 — Reihenfolge/Bündelung Stufe 1 / Stufe 2 / Runner.**
- frage: Werden Stufe 1 (Primitive) und Stufe 2 (SKILL.md-Zerlegung) als eigene Stories vor/nach dem Runner gebaut oder in einem Runner-Epic gebündelt?
- optionen: (a) Empfehlung des architekt: Stufe 1 zuerst (eigene fixture-getestete Stories) → Runner → Stufe 2 optional danach; (b) alles in einem Feature-Batch `F-###` (via `board-feature-drain.sh`); (c) nur Stufe 1 + Runner jetzt, Stufe 2 zurückstellen bis der Rest-LLM-Pfad-Anteil gemessen ist.
- quelle: §6 dieses Dokuments; Spec „Nicht-Ziele" (Owner-Entscheid Bündelung ausstehend).
- **Entscheid (Owner, 28.07.2026): (a)** — Stufe 1 zuerst als eigene, fixture-getestete Stories → Runner → Stufe 2 optional danach.

**Q6 — Scope-Grenze des ersten Runner-Schnitts bestätigen.**
- frage: Ist der Ausschluss von `--all`/`--parent`/`--plan`/SR1-Parallel/Design-interaktiv aus dem ersten Runner-Schnitt so gewollt (kleinster Blast-Radius), oder soll Phase E (Feature-Batch-Integration) schon mitgeplant werden?
- optionen: (a) erster Schnitt strikt board-weite Standard-Einzelrunde (Empfehlung); (b) Feature-Batch (Phase E) direkt mit einplanen; (c) auch SR1-Parallel im Runner-Scope (deutlich grösserer (c)-Anteil, höheres Risiko).
- quelle: §0 Anti-Ziel; §1.7; AC1 („eine Standard-Runde").
- **Entscheid (Owner, 28.07.2026): (a)** — erster Schnitt strikt board-weite Standard-Einzelrunde. Feature-Batch/SR1-Parallel bleiben vorerst beim LLM-Orchestrator.

**Q7 — Gate-Parser-Strenge (§5.1, AC7).**
- frage: Wie streng ist der mechanische Gate-Parser, bevor er an den Judge eskaliert?
- optionen: (a) exakt-Regex-only, jede Abweichung → Judge (sicherster S-047-Pfad, mehr Mini-Calls); (b) toleranter Parser (trim/case-insensitive/erste passende Zeile), Judge nur bei echtem Widerspruch (weniger Calls, minimal grösseres Rate-Risiko); (c) exakt-Regex + eine kleine, **fest dokumentierte** Normalisierung (nur Whitespace/Trailing), sonst Judge.
- quelle: AC3 (dieselben Gate-Tokens wie heute); AC7 (kein stilles Raten); Verträge-Abschnitt der Spec (Gate-Token-Liste).
- **Entscheid (Owner, 28.07.2026): (c)** — exakt-Regex + kleine, fest dokumentierte Normalisierung (nur Whitespace/Trailing), sonst Judge. Mittelweg zwischen Sicherheit und unnötigen Zusatz-Aufrufen.

---

## Anhang — ADR-Kurzliste

- **ADR-0** (§0): Runner = deterministischer Bash-Arm für die Standard-Runde; LLM-Orchestrator bleibt für Ermessen (Klasse c). Confidence: hoch. Reeval: `claude -p`-Kosten weichen ab.
- **ADR-1** (§6.1): Stufe-1-Primitive zuerst, fixture-getestet, werden vom Runner absorbiert (nicht obsolet). Confidence: hoch.
- **ADR-2** (§6.2): Stufe 2 unabhängig komplementär, nachrangig, ROI sinkt nach Stufe 3. Confidence: mittel.
- **ADR-3** (§7): schrittweise dogfood-first-Migration mit Decision-Trace-Audit statt Big-Bang/Doppel-Bau-Shadow; LLM-Orchestrator bleibt Ein-Flag-Rückfall bis Phase D. Confidence: hoch (S-047-Doktrin).
- **ADR-4** (§1.1-S0.7): `flow.md` ist im Runner-Pfad **nicht** die Durchsetzungsebene des Standard-Pfads; standard-pfad-relevante Lessons müssen ins Skript/in Fixture-Tests wandern. Confidence: mittel (Owner-Frage Q4).
