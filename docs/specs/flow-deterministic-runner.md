---
id: flow-deterministic-runner
title: Deterministischer /flow-Runden-Runner (Kontext-Diät Stufe 3)
status: active
version: 1
spec_format: use-case-2.0
area: flow-orchestrierung
---

# Spec: Deterministischer /flow-Runden-Runner (Kontext-Diät Stufe 3)  (`flow-deterministic-runner`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder`/`reviewer`/`tester` (bauen daraus), `architekt` (leitet daraus die konkrete Zustandsmaschine ab — s. Nicht-Ziele).
> **Diese Spec beschreibt das ZIEL, die zu erhaltenden Garantien und die Erfolgskriterien — sie entwirft NICHT die Zustandsmaschine selbst.** Der konkrete technische Entwurf (Bash-Runner-Architektur, Zustandsübergänge, Klassifikations-Tabelle je Ermessensfall) ist Aufgabe des `architekt`-Agenten im Folgeschritt und darf hier weder vorweggenommen noch dupliziert werden.

## Zweck
Die grösste Token-Kostenquelle einer langen `/flow`-Session ist nicht die Ausgabe, sondern dass der LLM-Orchestrator bei praktisch **jedem** Werkzeug-Schritt einer Runde den gesamten Fix-Kontext (die vollständige `skills/flow/SKILL.md` + den kompletten Gesprächsverlauf) neu aus dem Cache liest. Ein **deterministischer Runden-Runner** (Bash-Zustandsmaschine) übernimmt für **Standard-Runden** die heute vom LLM-Orchestrator rein mechanisch erledigte Arbeit (nächstes Item wählen, Claim setzen, coder/reviewer/tester als fokussierte Einzel-Sessions mit **minimalem** Kontext dispatchen, deren Gate-Handoff auswerten, bei PASS landen, bei CHANGES-REQUIRED/FAIL iterieren) — **ohne** einen grossen LLM-Orchestrator-Kontext am Laufen zu halten. Ein LLM-Orchestrator wird nur noch für **echte Ermessensfälle** gerufen. Ziel: messbar niedrigerer Token-Verbrauch pro Standard-Runde bei **erhaltenem Verhalten** aller heute abgedeckten Sonderfälle.

## Kontext & verwandte, einfachere Sparstufen
Die Token-Retro (research-app, 24-Story-`/flow`-Session) identifizierte drei Sparstufen. Diese Spec fokussiert **Stufe 3** (die grösste + riskanteste). **Stufe 1** und **Stufe 2** sind kleinere, risikoärmere Verbesserungen desselben Ziels und werden hier nur als **verwandter Kontext** referenziert — der `architekt` kann sie im selben Architektur-Entwurf mitlösen; der Owner entscheidet nach Vorliegen des Entwurfs, ob gebündelt oder getrennt umgesetzt wird:

- **Stufe 1 (Mechanik-Bündelung):** Die Claim-Sequenz (Token erzeugen, `status`/`claimed_by`/`claimed_at`/`branch` setzen, committen, pushen — heute 3+ Einzelschritte in `SKILL.md` §2) und der Abschluss (Metrik-Schreibvorgänge §2b, Dispo-Spiegel, Memory-Commit §7) in je **ein** deterministisches Skript bündeln — analog zum bereits bestehenden `scripts/board-ship.sh`, das denselben Trick beim Landen anwendet. Kein Verhaltensunterschied, nur weniger Werkzeug-Aufrufe.
- **Stufe 2 (Kontext-Diät via Lazy-Loading):** `skills/flow/SKILL.md` in einen schlanken Kern (Item wählen, claimen, coder→reviewer→tester, landen — was **jede** Standard-Runde braucht) plus separate Kapitel-Dateien für Sonderfälle (Feature-Batch-Modus §0/Feature-Scope, Wellen-Plan §0b/§0c, Design-Freigabe-Gate §2c, Metrik-Vertragsdetails §2b, SR1/SR2/SR3-Strategie-Regeln) zerlegen, die nur bei Bedarf gelesen werden. Kein Verhaltensunterschied, nur kleinerer Fix-Kontext pro Runde.

## Main Success Scenario — Standard-Runde ohne grossen LLM-Orchestrator
1. Der Runner holt den Board-Stand frisch (`git fetch`) und wählt **mechanisch** das nächste bereite Item (`board next`), inklusive Stale-Reclamation-Fallback.
2. Der Runner setzt den Claim über das **bestehende** Push-basierte Claim-Protokoll (`SKILL.md` §2 / [[story-claim-lock]], seit S-120) — er erfindet **kein** neues Claim-/Race-Protokoll.
3. Der Runner dispatcht `coder` als **fokussierte Einzel-Session mit minimalem Kontext** (nur Spec + Story + relevanter Diff — **nicht** die gesamte `SKILL.md`-Welt).
4. Der Runner dispatcht `reviewer` (minimaler Kontext) und **parst das Review-Gate mechanisch aus dem Handoff-Text** (`Review-Gate: PASS | CHANGES-REQUIRED`).
5. Bei `PASS`: `tester` (minimaler Kontext), **Test-Gate mechanisch geparst** (`Test-Gate: PASS | FAIL | SKIPPED-*`).
6. Bei beidseitigem `PASS`: der Runner landet über `scripts/board-ship.sh` (unverändert, rein mechanisch).
7. Bei `CHANGES-REQUIRED`/`FAIL`: der Runner stösst die nächste Iteration an (coder mit Findings), bis `PASS` oder Schleifenschutz greift.
8. Die Runde endet — der gesamte Standard-Pfad lief, ohne einen grossen LLM-Orchestrator-Kontext über die Runde hinweg zu halten.

## Alternative Flows
### A1: Mehrdeutiger / nicht ins Muster passender Gate-Text
- Lässt sich das Review-/Test-Gate **nicht** eindeutig einem der bekannten Muster (`PASS`/`CHANGES-REQUIRED`/`FAIL`/`SKIPPED-*`) zuordnen → **kein** mechanisches Raten. Der Runner eskaliert an ein **leichtes LLM-Urteil** (fokussierter Zusatz-Dispatch, nicht der grosse Orchestrator) oder an den Owner.

### A2: Echter Ermessensfall
- Klassifikation „Spec-Lücke oder normaler Bug", Design-Freigabe-Gate-Bewertung, Blockaden-Diagnose → der Runner ruft den **LLM-Orchestrator** (bzw. das dafür vorgesehene leichte Urteil) statt selbst zu entscheiden.

### E1: Session bricht mitten in der Runde ab (Recovery)
- **Flip-Fixer:** Story ist gelandet (Remote-PR `MERGED`), aber der Board-Status-Flip auf `Done` fehlt (Session endete mitten in der CI-Beobachtung) → der Mechanismus zieht den fehlenden Flip mechanisch nach (Remote-State-Prüfung, `flow/P3`-Muster), statt die Landung als gescheitert zu behandeln.
- **Claim-Releaser:** Story bleibt `In Progress` hängen, weil die Session mitten im Review-Loop abbrach → die verwaiste Reservierung wird über den bestehenden Stale-Reclamation-Pfad ([[story-claim-lock]] AC8) wieder aufgenommen/freigegeben, nicht dauerhaft blockiert.

### E2: Claim-Race mit paralleler Session
- Push-Ablehnung beim Claim → **kein** Rebase; der bestehende rebase-freie Re-Read-Ablauf ([[story-claim-lock]] AC2/AC3) entscheidet den Race. Der Runner **nutzt** dieses Protokoll, erfindet es nicht neu.

## Acceptance-Kriterien

- **AC1** — Für eine **Standard-Runde** (ein bereites Item, keine Sonderfälle) läuft der komplette Pfad Item-Wahl → Claim → coder→reviewer→tester → Landen deterministisch (Bash-Zustandsmaschine), **ohne** dass ein grosser LLM-Orchestrator-Kontext (vollständige `SKILL.md` + wachsender Gesprächsverlauf) über die Runde hinweg gehalten wird.
- **AC2** — coder/reviewer/tester werden als **fokussierte Einzel-Sessions mit minimalem Kontext** dispatcht (Spec + Story + relevanter Diff), **nicht** mit der gesamten `SKILL.md`. Kein Verhaltensunterschied der Agenten gegenüber heute.
- **AC3** — Das Review-Gate (`PASS`/`CHANGES-REQUIRED`) und das Test-Gate (`PASS`/`FAIL`/`SKIPPED-*`) werden **mechanisch aus dem Handoff-Text** ausgewertet — dieselben Gate-Tokens und dieselbe Verzweigung wie im heutigen `SKILL.md`-Build-Loop (§3/§4).
- **AC4** — Der Runner nutzt für Claim, Claim-Race und Stale-Reclamation **ausschliesslich** das bestehende Push-basierte Claim-Protokoll ([[story-claim-lock]], seit S-120) — **kein** neues Lock-/Race-Protokoll wird erfunden.
- **AC5** — Bei beidseitigem Gate-`PASS` landet der Runner über `scripts/board-ship.sh` (unverändert). Bei `CHANGES-REQUIRED`/`FAIL` stösst er die nächste Iteration an; der **Schleifenschutz N=3** (§3) bleibt in Kraft.
- **AC6** — **Klassifikations-Pflicht (Kern-Garantie, deckt A1/A2):** Der begleitende `architekt`-Entwurf klassifiziert **jeden** heute in `skills/flow/SKILL.md` vorhandenen Ermessensfall in **genau eine** von drei Stufen: (a) *rein mechanisch übernehmbar*, (b) *mechanisch mit Eskalations-Fallback* an ein leichtes LLM-Urteil oder den Owner, (c) *bleibt zwingend LLM-Ermessen*. Die Klassifikation ist **erschöpfend** über die gesamte `SKILL.md` durchzuführen; die Liste unter „Zu klassifizierende Ermessensfälle (Pflicht-Minimum)" ist das **verbindliche Minimum**, nicht die vollständige Menge.
- **AC7** — **Kein stilles Raten (Safety-Floor, deckt A1):** Für jeden als „rein mechanisch" (a) klassifizierten Fall existiert ein definierter Eskalations-Ausgang, sobald das erwartete Muster **nicht** eindeutig zutrifft (kein Default-Raten). Dies spiegelt den `board-ship.sh`-Grundsatz K1 („behauptet nichts, es prüft — bei jeder Unklarheit Abbruch/Eskalation statt Raten", S-047-Vorfall) auf die neuen mechanisierten Schritte.
- **AC8** — **Recovery-Garantie (deckt E1):** Der Mechanismus fängt die real beobachteten Abbruch-Fehlerklassen mindestens so gut ab wie die heutigen manuellen Bash-Workarounds: **Flip-Fixer** (gelandet, aber Status-Flip fehlt — Remote-State-Prüfung, `flow/P3`) und **Claim-Releaser** (Story hängt `In Progress` nach Abbruch — Freigabe/Reclamation über den bestehenden Stale-Pfad).
- **AC9** — **Kein Verhaltensunterschied bei den erhaltenen Sonderfällen:** Für jeden Ermessensfall, der (b) oder (c) klassifiziert wird, bleibt das nach aussen sichtbare Verhalten (Board-Statusübergänge, Blocked-Ausgänge, Gate-Semantik) identisch zum heutigen `SKILL.md`-Ablauf. Stufe-3 verlagert die **Ausführungsökonomie**, nicht die Entscheidungen.
- **AC10** — **Messbarer Token-Gewinn ohne Regression:** Für eine standard-runden-lastige Session sinkt der Token-Verbrauch pro Standard-Runde nachweisbar (kein wiederholtes Voll-Lesen der `SKILL.md`/des Verlaufs je Werkzeug-Schritt), ohne dass ein Gate, ein Board-Statusübergang oder ein Sonderfall-Ausgang gegenüber heute abweicht.
- **AC11** — **Single-Writer bleibt:** Board-Status wird weiterhin nur vom `/flow`-Orchestrator-Pfad geschrieben (der Runner ist dessen deterministischer Arm); die Metrik-Ledger bleiben Single-Writer `/flow` (K2, [[metrics-recording-reliability]]). Keine parallele Schreib-Quelle entsteht.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace flow-deterministic-runner#AC<n>` gemäss `knowledge/<lang>.md` → `## Spec-Tagging`.

## Zu klassifizierende Ermessensfälle (Pflicht-Minimum zu AC6)
Aus `skills/flow/SKILL.md` abgeleitet — **nicht erschöpfend gemeint**; der `architekt` vertieft und ergänzt bei der erschöpfenden Durchsicht. Jeder Eintrag ist einer der drei Stufen (a/b/c) zuzuordnen:

1. **SPEC-LÜCKE-Eskalation** (§3) — strukturelle/Scope-Lücke → Blocked, `/requirement` nötig; „nicht im Loop raten".
2. **Schleifenschutz N=3** (§3) — derselbe Befund überlebt 3 Iterationen → Blocked.
3. **Design-Freigabe-Gate** (§2c) — `docs/design.md` + `owner_approved`-Prüfung, designer-Dispatch, headless-vs-interaktiv, Blocked bei fehlender Freigabe.
4. **DB-Trigger-Zweitreview durch `dba`** (§3.2a) — Trigger-Heuristik (Label `db` / Datenzugriffs-Diff), beide Gates PASS Pflicht.
5. **SR1 — Hot-Spot-Serialisierung + parallele Worktrees** (§0a/SR1) — disjunkte vs. geteilte Dateien, Serialisieren vs. parallel, Test-Isolation.
6. **Feature-Batch-Modus** (§Feature-Scope, `--parent`) — Dossier-/Notes-Injektion, `--target-branch`, gebündeltes Landen ([[feature-batch-orchestration]]).
7. **Wellen-Plan-Revalidierung** (§0b/§0c, `--plan`) — Wellenbildung, mechanische Revalidierung vor jeder Welle ([[parallel-session-plan]]).
8. **ID-Block-Reservierung** (§3a/§5) — lazy Solo-Reservierung + Freigabe nach Landen ([[id-block-reservation]]).
9. **Blocked-Ausgänge aller Art** (§6) — Loop-Schutz, SPEC-LÜCKE, Design-Freigabe, `SKIPPED-NO-DOCKER`, Rollout-Gate FAIL/NEEDS-HUMAN.
10. **Rollout-Gate FAIL / NEEDS-HUMAN** (§5) — CI rot / manueller Eingriff → Blocked, Owner vorlegen.
11. **Projekt-Memory-Kuration** (§7) — Session-Ende-Kuration von `.claude/memory.md` ([[project-memory]]).
12. **Empty-Drain-Diagnose** (§1) — `board ready`/WAITING-Aggregat statt stummes Stoppen ([[empty-drain-diagnostics]]).
13. **Stale-Reclamation / „Geist-In-Progress"** (§2) — Übernahme verwaister Claims.
14. **Template-Diff = hartes Test-Gate + `SKIPPED-NO-DOCKER`-Human-Handoff** (§4) — DB-Subsystem-Smoke-Pflicht, kein Bypass.
15. **Post-Rebase-Verifikation** (`flow/P2`, §5) — Test-Run gegen finalen main-Stand nach Konfliktauflösung.
16. **Validate-Flag-Invalidierung** (§5a) — DB-Setup-Diff invalidiert `adoption_validated_at`.
17. **Session-Rotation** (§6, [[flow-session-rotation]]) — Default eine Story/Batch vs. `--all`.

**Session-beobachtete reale Fehlerklassen (Pflicht-Abdeckung, s. AC8/E1/E2):**
18. **Flip-Fixer** — gelandet, Status-Flip fehlt (Session endete in CI-Beobachtung).
19. **Claim-Releaser** — Story hängt `In Progress` nach Abbruch im Review-Loop.
20. **Claim-Race** — konkurrierende parallele Sessions; bestehendes Push-Protokoll seit S-120 nutzen, nicht neu erfinden.

## Verträge
- **Eingaben:** Board (`board next`/`board show`/`board set`), Spec-Referenz + `implements`-ACs der Story, Agent-Handoff-Texte (Gate-Zeilen), `.claude/profile.md` (merge_policy, default_branch, cost_mode).
- **Gate-Tokens (mechanisch geparst, unverändert zu heute):** `Review-Gate: PASS | CHANGES-REQUIRED`; `Test-Gate: PASS | FAIL | SKIPPED-NO-DOCKER | SKIPPED-DOC-ONLY`.
- **Wiederverwendete Bausteine (kein Neubau):** `scripts/board-ship.sh` (Landen), [[story-claim-lock]]-Push-Protokoll (Claim/Race/Stale), Metrik-Touchpoints ([[metrics-recording-reliability]]).
- **Ausgaben/Statusübergänge:** identisch zum heutigen `/flow` — `To Do` → `In Progress` → (`In Review`) → `Done` bzw. `Blocked`; Single-Writer `/flow`.

## Edge-Cases & Fehlerverhalten
- Mehrdeutiger Gate-Text → Eskalation an leichtes LLM-Urteil/Owner, **nie** mechanisch raten (A1/AC7).
- Session-Abbruch mitten in der Runde → Recovery über Flip-Fixer/Claim-Releaser (E1/AC8).
- Claim-Push abgelehnt → rebase-freier Re-Read-Ablauf ([[story-claim-lock]] AC2), **kein** neues Protokoll (E2/AC4).
- Metrik-/Cleanup-Fehler blockieren die Runde nie (K3), werden aber sichtbar gemeldet (keine stille Verschluckung).

## NFRs
- **Token-Effizienz (Primärziel):** kein wiederholtes Voll-Lesen der `SKILL.md`/des Gesprächsverlaufs je Werkzeug-Schritt einer Standard-Runde; Fix-Kontext pro Runde signifikant kleiner. Messbar gegen eine standard-runden-lastige Referenz-Session.
- **Sicherheits-Doktrin (Risiko-Bewusstsein, verbindlich):** Stufe 3 verlagert Ermessen von LLM auf Skript-Mustererkennung. Ein Fehler hier ist **unsichtbar** (falsch gelandete/übergangene Story), nicht laut wie ein Skript-Crash. Genau deshalb übernahm `board-ship.sh` historisch **nur** den rein mechanischen Lande-Schritt (nach dem S-047-Vorfall: 9 Dateien durch eine LLM-Fehleinschätzung verloren) und **nicht** Item-Wahl/Gate-Bewertung. Der Entwurf MUSS diese Doktrin wahren: jede Mechanisierung eines heutigen Ermessensfalls braucht einen definierten Eskalations-Ausgang (AC6/AC7), und die Klassifikation ist die zentrale Risiko-Kontrolle dieser Feature.

## Nicht-Ziele
- **Keine Architektur/Zustandsmaschine in dieser Spec.** Der konkrete Runner-Entwurf (Zustände, Übergänge, Klassifikations-Tabelle je Ermessensfall, Skript-Schnitt für Stufe 1, Datei-Zerlegung für Stufe 2) ist Aufgabe des `architekt`-Agenten — hier nicht vorwegnehmen.
- **Keine Abschaffung des LLM-Orchestrators.** Er bleibt für echte Ermessensfälle (Stufe c) zwingend erhalten.
- **Keine Änderung der bewährten mechanischen Reichweite von `board-ship.sh`** über das für den Runner Nötige hinaus.
- **Kein neues Claim-/Race-/Lock-Protokoll** (bestehendes S-120-Protokoll nutzen).
- **Owner-Entscheid ausstehend**, ob Stufe 1+2 im selben Entwurf gebündelt umgesetzt werden — diese Spec fokussiert Stufe 3 als Ziel.

## Abhängigkeiten
- [[story-claim-lock]] — Push-basiertes Claim-/Race-/Stale-Protokoll (S-120), wird genutzt.
- `scripts/board-ship.sh` — deterministischer Lande-Schritt (Vorbild + wiederverwendet).
- [[flow-session-rotation]] · [[parallel-session-plan]] · [[feature-batch-orchestration]] · [[id-block-reservation]] · [[design-owner-approval]] · [[empty-drain-diagnostics]] · [[project-memory]] · [[metrics-recording-reliability]] — die Sonderfälle/Verträge, deren Verhalten der Runner erhalten muss (Klassifikations-Katalog AC6).
- **Folge-Schritt:** `architekt`-Entwurf (`docs/architecture/…`) mit der Klassifikations-Tabelle + Zustandsmaschine — separate Arbeit, hier nur referenziert.
