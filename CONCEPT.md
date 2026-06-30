# Softwareschmiede — Konzept & Anforderungen (Arbeitstitel: `agent-flow`)

> Status: **Requirements/Konzept-Phase** — noch kein Code. Lebendiges Dokument, wird iteriert.
> GitHub-Org (Ziel): `Studis-Softwareschmiede`. Plugin-/Repo-Name: **offen** (Arbeitstitel `agent-flow`).
> Dieses Repo ist bewusst **projekt- und sprach-neutral**: keine Pfade, Namen, Schemata eines konkreten Projekts.

---

## 1. Vision

Eine wiederverwendbare, **selbst-verbessernde Software-Fabrik** als Claude-Code-Plugin. Auf beliebige
Projekte beliebiger Sprache (Flutter, HTML, Java, …) ansetzbar. Jedes Projekt wird nach demselben
Prinzip abgewickelt: **coder → reviewer → tester**, bis es passt. Die Agenten werden über die Zeit
durch zwei Meta-Agenten (Retro + Training) besser — versioniert, geprüft, propagiert an alle Projekte.

## 2. Leitentscheidungen (bereits getroffen)

| # | Entscheidung | Wert |
|---|---|---|
| 1 | Maschinen | **mehrere** |
| 2 | Ausführung | **alles interaktiv** (unter Claude-Abo) → **keine API-Pro-Token-Kosten**, keine headless/Cloud-Ebene |
| 3 | Self-Improvement | **PR + Gate** (nie Direkt-Edit der Live-Skills) |
| 4 | Deploy | per **Push → GitHub Actions** (kostenloses CI, kein Claude) |
| 5 | Verteilung | **Repo-first, Plugin-ready** — rohes git-Repo + `~/.claude`-Symlink + `git pull`; Plugin-Hülle (`plugin.json`/`marketplace.json`) ist additiv und kommt später, wenn Multi-Maschine-Reibung oder der `stable`-Kanal gebraucht wird |

**Kostenfolge:** laufender Betrieb vom Abo gedeckt; keine separate API-Rechnung. (Wer später unattended
über die API automatisieren will, verlässt dieses Modell bewusst.)

**Cost-Mode (Token-Hebel).** Das Abo ist zwar pro-Token-kostenfrei, hat aber **Nutzungs-Limits** (5h-/Wochen-Fenster). Damit ein Lauf zwischen *sparsam* und *maximaler Qualität* wählbar ist, steuert ein **Cost-Mode** (`low-cost | balanced | max-quality`) pro Lauf, **mit welchem Modell jeder Agent dispatcht** wird — ein günstigeres Modell für Wegwerf-Prototypen, das teuerste für kritische Reviews/Tests/Retros. `balanced` ist der Default und entspricht dem bisherigen Zustand (das `model:`-Frontmatter jedes Agenten) — **kein Regress**. Auflösung: `--cost`-Argument > `profile.cost_mode` > `balanced`. Die Rolle×Modus-Matrix + Mechanik sind eine eigene Quer-Achse: `docs/architecture/model-tier-subsystem.md` (Referenz-Tabelle: `knowledge/model-tiers.md`).

## 3. Eine Ebene, kein Cloud-Plane

```
INTERAKTIV (du am Keyboard, Claude-Code unter Abo)
  /flow <task>   → coder → reviewer ⇄ Loop (bis Review-Gate: PASS) → tester → fertig
  /retro         → Retro-Agent: gesammelte Lessons → Skill-Verbesserung (als PR)
  /train <lang>  → Training-Agent: Web-Recherche neuer Patterns → Skill-/Profil-Update (als PR)
  /agent-flow:upgrade [<repo>]  → Upgrade-Orchestrator: Versionen erkennen → Kompat-Solver → UpgradePlan
                   aufs Board → autonom via /flow modernisieren → retro. NICHT bloß "/upgrade" tippen —
                   das ist ein CLI-Built-in (Abo-Upgrade); nur die namespaced Form erreicht das Skill.
                   (Spec: docs/architecture/upgrade-subsystem.md)

GITHUB (kostenlos, ohne Claude)
  Push → Actions → Build + Deploy        |   Projects v2 → Kanban/Scrum-Board pro Projekt
```

Beide Meta-Agenten (Retro/Train) und der Kern-Loop nutzen **dieselben** versionierten Agent-Skills.

## 4. Die Agenten

Generisch + **sprach-adaptiv** (kein per-Sprache-Agent; stattdessen ein neutraler Agent + per-Projekt-/
per-Sprache-Wissen, das er zur Laufzeit liest). Sprach-Spezifika kommen aus dem Projekt-Profil und den
vom Training-Agent gepflegten Sprach-Wissensdateien.

- **requirement** — verfeinert eine vage Anforderung in eindeutige, eigenständig umsetzbare TODOs und schreibt sie priorisiert aufs Board (Front-of-Funnel). Fragt **iterativ in Runden von max. 2–3 Fragen** nach, bis die Anforderung eindeutig UND in kleine Pakete zerlegbar ist. Schreibt KEINEN Code.
- **architekt** (Design) — definiert die App-Architektur (Struktur/Komponenten/Layer/Tech) → bindende `docs/architecture.md`. Kein Code.
- **dba** (Design) — erarbeitet das Datenmodell (Entitäten/Relationen/RLS-Konzept) → bindende `docs/data-model.md`; der `coder` implementiert es. Kein Code/keine Migrationen.
- **designer** (Design, optional/UI) — definiert Design-System + UX/Visual-Vorgaben (Palette/Spacing/Typo/Komponenten/A11y) → bindende `docs/design.md`. Kein Code. Design-Review macht der `reviewer` via UI-Pack-Checklist (kein eigener Design-Reviewer).
- **coder** — implementiert eine Aufgabe; liest Projekt-Kontext + Lessons + Profil + Design-Docs; testet selbst; übergibt zum Review.
- **reviewer** — prüft, kategorisiert `Critical / Important / Suggestions`, gibt `Review-Gate: PASS | CHANGES-REQUIRED`. Critical+Important sind der Arbeitsauftrag zurück an den coder.
- **tester** — der Abschluss nach Review-PASS: **Default „Build + Smoke"**, pro Projekt-Profil auf echte Test-Suite/E2E erweiterbar; eigenes Gate.
- **retro** (Meta) — destilliert die gesammelten Lessons-learned in Verbesserungen der Agent-Skills. Schreibt als **PR**.
- **train** (Meta) — recherchiert im Netz aktuelle Patterns/Best-Practices je Sprache, fließt in Skills/Sprach-Profile ein. Schreibt als **PR**.
- **cicd** — ausführender Abschluss-Arm des Orchestrators ab tester-PASS: git-Landen (merge+push gemäss `merge_policy`), GitHub-Workflow beobachten (CI-Watch), lokaler Docker-Rollout (pull + recreate, NIEMALS restart), Disk-Hygiene (`docker image prune -f`, Pflichtschritt). Zusätzlich: Rollback, Build-Metadaten/Versionsstempel (zur Build-Zeit via Docker ARG/ENV), laufende CI-Pipeline-Pflege. Kein App-Code. Dispatcht via SHIP-TRIGGER direkt nach tester-PASS oder manuell via `/cicd ship`. Abgrenzung: `/preview` = ephemerer Dev-Preview; `/cicd ship` = vollständiger produktiver Abschluss (landen + CI + Rollout + Prune).
- **teamLeader** (Meta, *später*) — gliedert einen NEUEN Agenten ins Team + den Workflow ein (Spec + Verdrahtung in Handoff-Kette/Skills), via **PR+Gate**. Selbst-Erweiterung der Fabrik; nicht P1.

### Kern-Loop (aus dem Brewing-Projekt übernommen, hier generisch)
coder finished → Handoff → reviewer → bei `CHANGES-REQUIRED`: Critical+Important zurück → fix → erneut →
bis `PASS` → tester. **Schleifen-Schutz:** derselbe Befund überlebt max. 3 Iterationen, dann Abbruch + Vorlage an den User.

## 4a. Pipeline: requirement → Board → /flow (der Betrieb)

Das GitHub-Board ist nicht nur Anzeige, sondern **Arbeits-Queue UND persistenter Zustand**:

**Vorgelagert (Design):** `architekt` (+ `dba` bei DB-Domäne) erzeugen die bindenden Design-Docs `docs/architecture.md` / `docs/data-model.md`, *bevor* `requirement` zerlegt — `coder`/`reviewer` behandeln sie als Constraints.

1. **`requirement`-Agent** verfeinert die Anforderung in einzelne, eigenständig umsetzbare TODOs und schreibt sie als Items aufs Board (Spalte **To Do**) — mit **Reihenfolge/Priority** und notierten harten Abhängigkeiten („braucht #3").
2. **`/flow` (Orchestrator = die interaktive Haupt-Session)** liest das Board (To Do, in Reihenfolge) und arbeitet **Punkt für Punkt**:
   - Item → **In Progress** → `coder → reviewer ⇄ Loop → tester` → bei PASS → **Done** (+ PR/Commit ans Item verlinkt) → nächstes Item.
   - Kommt ein Item nicht durch (3-Iterationen-Schleifenschutz) → **Blocked**, Meldung an den User, Rückfrage ob mit den restlichen Items weiter.
3. **Interaktiv:** der User triggert `/flow`, kann zwischen Items eingreifen, stoppen, umpriorisieren. Bricht eine Session ab, zeigt das Board den Stand → jederzeit fortsetzbar.

**Board-Spalten:** `To Do │ In Progress │ Blocked │ In Review │ Done`.

**Defaults:** (1) Reihenfolge via Priority-Feld + Abhängigkeits-Notiz; (2) jedes Item ≈ ein coder→reviewer→tester-Durchlauf (Slicing ist `requirement`-Aufgabe); (3) Fehlschlag → Blocked + Rückfrage; (4) bei Done PR/Commit ans Item hängen.

## 4b. /flow-Spine & Handoff-Verträge (akzeptiert)

**Board-Item-Vertrag:** Title + **Acceptance Criteria** (Body) + Priority/Order + optional Depends-on + Status (**nur** der Orchestrator schreibt Status). *(Mit §4d ausgelagert: die Acceptance-Criteria leben durable in `docs/specs/<feature>.md`; das Item referenziert die **Spec-ID** statt sie zu enthalten.)* *(Additive Erweiterung durch **`/upgrade`**: dieser Skill legt initial die UpgradePlan-Spec + die Leiter-Items an und schreibt nach Abschluss die Ziel-Versionen ins `profile` zurück — begründete Ausnahme vom „nur `/flow` schreibt"-Prinzip; alle **Item-Status-Übergänge** und Code-PRs bleiben Orchestrator-Hoheit. Spec: [`docs/architecture/upgrade-subsystem.md`](docs/architecture/upgrade-subsystem.md) §3/§7.)*

**`/flow`-Ablauf** (cwd = Ziel-Projekt-Repo):
0. Board-Ref aus `.claude/profile.md`.
1. Nächstes „To Do" (höchste Priority, dessen Depends-on alle „Done") → **In Progress**. (keins → „Board leer".)
2. LOOP (≤ 3 Iterationen): `coder → reviewer`. CHANGES-REQUIRED → Critical+Important zurück an coder → erneut; PASS → weiter. Schleifenschutz erschöpft → **Blocked** + Kommentar + Meldung an User.
3. `tester` (interaktiv). FAIL → zurück an coder (zählt zum Schutz); PASS → weiter.
4. **`cicd ship`** (bei `profile.deploy == docker`): Orchestrator dispatcht `cicd` mit SHIP-TRIGGER → cicd landet den Code (merge+push gemäss `merge_policy`), beobachtet den CI-Lauf, führt lokalen Rollout + `docker image prune -f` durch. Rollout-Gate: PASS → Item **Done** (+ PR/Commit verlinkt); FAIL/NEEDS-HUMAN → **Blocked** + Kommentar → nächstes Item oder User-Rückfrage.
   Bei `deploy != docker` oder explizit aufgeschobenem Rollout: Orchestrator landet selbst (bisheriges git-Verhalten); cicd wird separat manuell aufgerufen.

**Handoff-Marker** (generalisiert aus Brewing):
- coder → `Review-Handoff: REVIEW REQUIRED (#<n>, Iteration <N>)`
- reviewer → `Review-Gate: PASS | CHANGES-REQUIRED` + `## Critical / ## Important / ## Suggestions` (Critical+Important = Arbeitsauftrag)
- tester → `Test-Gate: PASS | FAIL` + Ran/Failures

**Entschieden:**
- **Code-Landing = PR pro Item** (Default), via `merge_policy: pr|direct` im Projekt-Profil auf Direkt-auf-`main` umstellbar. PR-Modus nutzt die „In Review"-Spalte + deinen Merge-Approve.
- **Tester läuft interaktiv** im `/flow`-Lauf (sofortiges PASS/FAIL). CI-Tester (Actions auf dem PR) optional später, nur im PR-Modus.

## 4c. Sprach-/Domänen-Expertise: Knowledge Packs (statt per-Sprache-Agenten)

Trennung **Rolle (Prozess) ≠ Expertise (Wissen)**: die Rollen-Agenten (coder/reviewer/tester) sind generisch; die Sprach-/Domänen-Expertise liegt in versionierten **Knowledge Packs** in der Fabrik:

```
agent-flow/knowledge/  flutter.md  html.md  java.md  js.md  sql.md  …
```

- **Laden zur Laufzeit:** `coder`/`reviewer`/`tester` lesen — zusätzlich zu Profil/Lessons — die Pack(s) gemäß `profile.language` (+ optional `profile.domains`, z.B. `sql`/`security`/`accessibility`). So „wird" der generische coder für die Aufgabe z.B. ein Flutter-Coder.
- **Pack-Aufbau** (Abschnitte je Rolle): `## Coder-Guidance` (Idiome/Patterns/Fallen) · `## Reviewer-Checklist` (sprachspez. Critical/Important) · `## Test-Approach`.
- **Domänen statt nur Sprachen:** DBA/Security/A11y/Architektur sind Packs (`sql.md`, `security.md`, `architecture.md`, …), die die jeweilige Rolle dazulädt (`architekt`→`architecture.md`, `dba`→`sql.md`, `coder` bei berührter Domäne) — ersetzt das Brewing-`dba-coder` sauber.
- **Selbst-verbessernd:** `train` recherchiert neue Patterns je Sprache → schreibt (PR+Gate) in `knowledge/<x>.md`; `retro` hebt wiederkehrende Projekt-Lessons in die Packs. **Neue Sprache = neue Datei, kein neuer Agent.**
- **Seed-Packs zu Beginn:** `flutter`, `html`, `css`, `tailwind`, `angular`, `java`, `js`, `sql` (+ `architecture` und `security` als Domänen). UI-Frameworks (Angular/Tailwind/CSS/HTML) sind **Packs**, kein eigener Agent.
- **Security ist querschnittlich + angehoben** (gebaut): `knowledge/security.md` mit **⚑ Floor**, den `coder`/`reviewer` **immer** anwenden (auch ohne `domains:[security]`, weil Build/Smoke Sicherheitslücken nicht sehen); voller Pack bei `domains:[security]`. Dazu automatisch: CI-**Secret-Scan** (gitleaks, harter Gate vor dem Image) + `tester`-Security-Smoke (Secret-Scan + Dependency-Audit); security-relevante Anforderungen werden **AC** (→ Drift-Gate). KEIN eigener security-reviewer-Agent (Pack-Prinzip). **Aktualität (zweigeteilt):** *durable Prinzipien* hält `train security` frisch (`last_trained`-Datum im Pack + `/flow`-Nudge bei > 90 Tagen); *tagesaktuelle Bedrohungsdaten* (CVEs/Exploits) laufen NICHT in den LLM-Pack (würde halluzinieren/veralten), sondern über Claude-freie GitHub-Automatik: `dependabot.yml` (kontinuierliche Dependency-/Action-Vuln-PRs) + geplanter `security.yml`-Scan (gitleaks-History → Issue) → Board-Item → Fix via `/flow`.

## 4d. Spec-getriebene Entwicklung: Concept → Detailkonzept → Spec → Code (durable Docs)

**Grundsatz:** Jede Weiterentwicklung läuft **Konzept → Detailkonzept → Spezifikation → Umsetzung**. Die ersten drei Schichten sind **durable, versionierte, sprach-/paradigma-unabhängige** Dokumente und die **Source of Truth** — der Code ist nachgelagert und (z.B. bei einem Sprach-Port) ersetzbar. Ziel: eine App lässt sich aus Konzept+Spec neu bauen, ohne den Alt-Code zu lesen.

**Warum lasttragend, nicht dekorativ:** die Spec rottet nur, wenn niemand sie konsumiert. Hier liegt sie auf dem kritischen Pfad — `coder` baut aus ihr, `tester` testet aus ihren Acceptance-Kriterien, `reviewer` prüft gegen sie. Eine veraltete Spec erzeugt falschen Code/Test und fliegt im Gate auf → selbst-korrigierend statt Disziplin-abhängig.

**Wo (entschieden): `docs/` im App-Repo**, versioniert neben dem Code → Code- und Doc-Änderung im selben PR (Drift-Kontrolle dadurch natürlich). Beim **Sprach-Port** wird `docs/` ins neue Repo **geseedet** (kopiert) → portabel by construction.

**Drei Schichten (entschieden) — einheitliches, sprach-neutrales Skelett aus `templates/_docs/`:**

```
docs/
  concept.md         # Konzept:       Problem · Nutzer · Ziele · Nicht-Ziele · Scope.        Ändert selten.
  architecture.md    # Detailkonzept: Domänenmodell · Geschäftsregeln (BR-NNN, zentral) · Komponenten ·
                     #                Kern-Flows · Zustände · NFRs · Entscheidungen (ADR-Stil).
                     #                Logisch, nicht sprachlich.
  data-model.md      # (DB-Domäne)    Entitäten · Relationen · RLS-Konzept — Teil des Detailkonzepts.
  design.md          # (UI-Domäne)    Design-System/UX-Vorgaben — Teil des Detailkonzepts.
  specs/<feature>.md # Spezifikation: ID · Zweck · (optional) Main/Alternative Flows · Acceptance-Kriterien
                     #                (nummeriert, testbar, referenzieren BR-NNN) · Verträge (I/O, API, Schema)
                     #                · Edge-Cases/Fehler · NFRs · Nicht-Ziele · Abhängigkeiten · Status/Version.
  glossary.md        # Ubiquitous Language (stützt die Sprach-Unabhängigkeit).
```

**Vereinheitlicht die bisherigen Design-Docs:** die früher in `.claude/` gedachten `architecture.md`/`data-model.md`/`design.md` (von `architekt`/`dba`/`designer`) wandern **unter `docs/`** — sie SIND das Detailkonzept. Und die bisher nur im **Board-Item** lebende **Acceptance-Criteria (§4b)** wird in `docs/specs/<feature>.md` **durable**; das Board-Item *referenziert* künftig eine **Spec-ID** statt die Kriterien selbst zu enthalten.

**Authoring (entschieden: Hybrid):**
- `requirement` legt/aktualisiert die Specs (+ ggf. `concept`/`architecture`) **vor** dem Board-Item; sein Q&A bleibt transient, der **Doc-Output wird committet** (durable).
- `coder` baut **aus der Spec-Sektion**; kleine, im Build entdeckte Lücken darf er **direkt in der Spec nachziehen** (`reviewer` prüft Deckung).
- Größere/strukturelle Abweichungen → Item **Blocked**, zurück an `requirement` (Mensch entscheidet).

**Drift-Gate (entschieden: hart):** der `reviewer` blockt (`CHANGES-REQUIRED`), wenn ein Diff **beobachtbares Verhalten** ändert/erweitert, das nicht in der Spec steht. Heuristik „beobachtbares Verhalten": neue/geänderte Endpunkte, UI-Flows, Ein-/Ausgaben, Fehler-/Statuscodes, Datenfelder, NFR-relevante Limits. Reiner Refactor/Typo ohne Verhaltensänderung → keine Spec-Pflicht (**Proportionalität**). **Code und Spec landen im selben PR — zusammen oder gar nicht.**

**Bestehende Apps / Reverse-Engineering (entschieden: eigener Schritt):** `/init` (Repo adoptieren) bietet einen **einmaligen, mensch-validierten** Schritt „**Spec aus Code ableiten**": liest den Code → erzeugt `docs/concept.md` + `architecture.md` + `specs/` als Entwurf → Mensch reviewt/korrigiert → committen. Erst danach ist die App **portierbar** und unter Drift-Gate. (Macht auch die bestehenden Brewing-Apps dokumentier-/portierbar.)

**Reconcile (rückwärtige Aufholung, entschieden):** Das Drift-Gate verhindert nur *neue* Drift im `/flow`-Fluss, die Spec-Ableitung läuft nur *einmal* bei der Adoption — **akkumulierte** Abweichung (Direkt-Commits, Pre-Adoption-Bestand, fremder Upstream) holt `/adopt reconcile` als **wiederkehrender Code→Doc-Abgleich** auf: `reviewer`-Audit-Modus erkennt die Drift (abgeleitet, gleiche Heuristik wie das Gate) → Owner entscheidet pro Drift die Richtung (doc-nachziehen | code-rückbau | →requirement | won't-fix) → Doc-Updates als PR, Rückbauten als Board-Item; durable Entscheidungs-Historie in `docs/spec-audit.md`. Kein Auto-Fix, kein eigener Agent. Vertrag: `docs/architecture/reconcile-subsystem.md`.

**Sprach-Port (A → B):** neues Repo → `docs/` seeden → `profile.md` auf Sprache B → Board aus den Specs neu generieren → `/flow`. Der `coder` baut alles **aus den Specs**; der Alt-Code wird nicht gelesen.

**Traceability:** Spec-ID → Board-Item → Commit/PR → **Test** (`@trace <slug>#AC/BR` im Testcode) —
durchgängig, in beide Richtungen. Der `tester` rechnet ein **Coverage-Gate** (jede genannte AC + jede
referenzierte BR ≥ 1 deckender Test); die Map ist **abgeleitet**, nie handgepflegt. Sprach-neutraler
Vertrag + kanonisches Token: `docs/architecture/traceability-subsystem.md`; Idiom je Sprache im
Knowledge Pack (`## Spec-Tagging`).

**Touchpoints (Umsetzung später):** `templates/_docs/` (4 Skelette) · `new-project` (scaffoldet `docs/`) · `requirement` (schreibt durable Docs + Board mit Spec-IDs) · `/init` (Reverse-Eng-Schritt) · `coder` (Quelle = Spec; darf Lücken nachziehen) · `reviewer` (Drift-Gate + Spec-Konformität) · `tester` (Tests aus Acceptance-Kriterien) · `/flow` (lädt Spec pro Item; Landen = Code+Spec im selben PR). **Abgrenzung:** Im Brewing sind `requirement-analyst`-Specs bewusst *transient/gitignored* — die Fabrik macht hier das Gegenteil: nur das *Q&A* bleibt flüchtig, der **Spec-Output ist durable**. Zwei getrennte Projekte, zwei Lebenszyklen; nicht vermischen.

## 5. Self-Improvement mit PR + Gate (das Sicherheits-Herzstück)

Retro/Train ändern **nie** direkt die Live-Skills. Ablauf:
1. Agent erstellt Branch + **Pull Request** mit dem Skill-Diff (sichtbar, reversibel).
2. **Gate** (kombinierbar): (a) der eigene `reviewer` prüft das Diff = muss PASS; (b) Skills laufen gegen ein Mini-Beispielprojekt — wird's besser?; (c) menschliches „Approve".
3. Erst nach grünem Gate → merge `main` → **neue Plugin-Version** → propagiert beim nächsten `/plugin marketplace update` an alle Projekte.
4. GitHub **Branch-Protection** auf `main`: require PR + require check/approval; Agenten haben **keinen** Direkt-Push auf `main`.

**Entschiedene Default-Gate-Stufe:** (a) `reviewer`-Check **+** (c) menschliches Approve vor Merge. Der Beispielprojekt-Test (b) kommt später dazu.

→ Selbst-*Verbesserung* statt Selbst-*Degradation*: jede Änderung prüfbar, versioniert, zurückrollbar.

## 5a. Observability & Effectiveness (Tier 1)

Damit Self-Improvement **messbar** bleibt (nicht im Kreis dreht):

**Übersicht (Traceability):**
- **Improvement-Board** — eigenes GitHub Project der Fabrik (Dogfooding). Jede `retro`/`train`-Promotion = Karte: `Proposed → Merged → Measuring → Validated | Reverted`.
- **`LEARNINGS.md`** im Fabrik-Repo — Ledger, eine Zeile pro Promotion: `| ID | Datum | Pack | Regel | Quelle | PR | Status |`. `retro`/`train` hängen sie als Teil ihres PR an.

**Messbarkeit (Effectiveness):**
- **Regel-IDs:** jede Pack-Regel hat eine stabile ID (`flutter/R007`, `sql/R003`).
- **`reviewer` taggt** jeden Befund mit der Regel-ID, gegen die verstoßen wurde (oder „neu").
- **Maßstab:** kehrt der adressierte Fehler weiter wieder? Wiederkehr sinkt nach Promotion → Ledger-Status `Validated`; kein Effekt/schädlich → `git revert`, Status `Reverted`.

**Reversibilität** eingebaut: jede Promotion ist Commit/PR → schlechte Lektion zurückrollbar.

**Tier 2 — Metrik-/Performance-Subsystem:** `/flow` loggt pro Item Metriken (Iterationen-bis-PASS, #Critical/Important, Test-First-Pass, Blocked, Wall-Clock, Effort Points) + Soll-Ist-Abrechnung + Retro-Effektivitätsmessung via Regel-ID-Defektraten. Ausgestaltung, Datenmodell (JSONL-Ledger), EP-Formel und Rollout-Phasen: **[`docs/architecture/metrics-subsystem.md`](docs/architecture/metrics-subsystem.md)** (Source of Truth für Tier 2).

Touchpoints: `reviewer` (Regel-ID-Tagging), `retro`/`train` (Ledger + Board pflegen), `/flow` (einziger Metrik-Schreiber).

## 6. Verteilung: Repo-first, Plugin-ready

**Grundsatz:** Ein Plugin *ist* ein git-Repo + dünne Verpackung (zwei JSON-Dateien). „Repo oder Plugin" ist keine echte Alternative — es ist immer ein Repo; die Plugin-Hülle ist additiv und jederzeit nachrüstbar. Darum:

- **Jetzt — rohes Repo:** Repo unter der Org, Layout `agents/` + `knowledge/` + `templates/` + `skills/` (`flow`, `retro`, `train`, `new-project`) im Root (= zufällig schon Plugin-Layout). Konsum per Symlink nach `~/.claude/` (user-level → gilt in allen Projekten), Verbesserungen per `git pull` je Maschine.
- **Später — Plugin-Hülle (additiv):** sobald Multi-Maschine-Reibung oder ein sauberer Release-Kanal gebraucht wird, kommen `.claude-plugin/plugin.json` + `marketplace.json` dazu. Dann: Installation per `/plugin marketplace add <org>/<repo>` + `install`, Updates per `/plugin marketplace update`, und ein **`stable`-Kanal** (Projekte) getrennt von `main` (Entwicklung) → passt exakt zu PR+Gate: PR→`main`→Gate→Promotion `main`→`stable`→*dann* sehen's die Projekte.
- Plugin-Agenten sind **nicht** namespaced → vom Orchestrator wie normale Agenten aufrufbar; können sich gegenseitig referenzieren.

**Warum nicht gleich Plugin:** für solo/wenige Maschinen ist der Plugin-Mehrwert klein; rohes Repo ist beim *Bauen* des Frameworks angenehmer (in-place editieren). Plugin-Layout-Disziplin halten wir trotzdem ein, damit die Hülle gratis bleibt.

## 7. Layout & Per-Projekt-Zustand (Fabrik bleibt neutral)

**Wo was liegt:**
```
GitHub-Org  Studis-Softwareschmiede        ← Container für ALLES
├── agent-flow/      ← die Fabrik (EINMAL): generische agents/ + skills/, projekt-neutral
├── projekt-A/   ┐
├── projekt-B/   │   je ein EIGENES Repo — GESCHWISTER von agent-flow,
└── projekt-C/   ┘   NICHT in agent-flow verschachtelt
```
- „Darunter" gilt auf **Org-Ebene**, nicht im Dateisystem: die Org enthält die Fabrik + alle Projekt-Repos als **Geschwister** (keine verschachtelten git-Repos). Die Fabrik ist kein Parent, sondern bedient die Projekte.
- **Fabrik-Agenten werden global geladen** (`~/.claude`-Symlink bzw. später Plugin) → in **jedem** Projekt-Repo verfügbar, egal wo es lokal liegt. `/flow` läuft mit cwd = Ziel-Projekt-Repo und liest **dessen** `.claude/profile.md` → **dessen** Board.

Pro Zielprojekt, **nicht** in der Fabrik:
- `CLAUDE.md` — Projekt-Kontext (Stack, Konventionen, Deployment).
- `.claude/profile.md` — Sprach-/Build-Profil: Sprache, Build-/Test-/Lint-Befehle, Smoke-Probe, **`merge_policy: pr|direct`**, **Board-Referenz** (GitHub-Project-Nummer). Orchestrator/coder lesen das, statt etwas hart zu kodieren.
- `docs/concept.md` + `docs/architecture.md` (+ `docs/data-model.md` / `docs/design.md` je Domäne) + `docs/specs/<feature>.md` + `docs/glossary.md` — **durable, sprach-neutrale Source of Truth** (§4d): Konzept → Detailkonzept → Spec. `architekt`/`dba`/`designer` schreiben das Detailkonzept, `requirement` Konzept+Specs; `coder`/`reviewer`/`tester` behandeln sie als bindende Constraints (Spec-/Architektur-/Modell-/Design-Konformität = Review-Kriterium, hartes Drift-Gate). *(Ersetzt die früher unter `.claude/` gedachten Design-Docs.)*
- `.claude/lessons/{coder,reviewer,tester}.md` — **projekt-isolierte** Lessons (Reviewer schreibt hierhin, coder liest). Kein Cross-Contamination, Fabrik bleibt sauber.
- GitHub **Project (v2)** — eigenes Kanban/Scrum-Board pro Projekt (Status-Board + Iteration-Felder für Sprints); via `gh project`/GraphQL automatisierbar.

**Woher diese Dateien kommen:** der `new-project`-Skill (Neuanlage) bzw. `init` (bestehendes Repo adoptieren) erzeugt sie beim **Bootstrap** aus `templates/<lang>/`: Repo + Board v2 anlegen, Stack erkennen → `profile.md` (Build/Test/Lint/Smoke, `merge_policy: pr`, Board-Ref, `deploy: docker` [profil-überschreibbar], `image: ghcr.io/<org>/<name>`, `registry: ghcr`), minimale `CLAUDE.md` (Template + 1–2 Rückfragen), leere `lessons/*`, plus **`Dockerfile` + CI-Workflow** (Build → Push nach ghcr.io via eingebautem `GITHUB_TOKEN`) und **Branch-Protection** (require PR + `reviewer`-Check; solo: kein Pflicht-Human-Approval, du mergst selbst). `requirement` *konsumiert* das nur. **Lifecycle: `new-project`/`init` → `requirement` → `/flow`.** Für **bestehende fremde Repos**: **`/adopt <owner/repo>`** = clone (fremd → Fork in die Org) → `init` (Spec aus Code) → **Audit** (reviewer Audit-Modus + gitleaks/dep-audit gegen Security-Floor/Packs/abgeleitete Spec) → priorisiertes **Backlog** aufs Board → `/flow`. Behebt nichts automatisch; pusht nie ungefragt aufs Upstream. **Stack-Entscheidung:** finale Wahl beim User; `architekt` berät/schlägt vor, wenn nicht vorgegeben; `init` erkennt aus dem Code; sie lebt in `profile.md` und steuert Pack-Laden/Templates/Design-+DBA-Aktivierung. Detail-Spec: `AGENTS.md`.

## 8. GitHub-Integration

- **Voller GitHub-Zugang via GitHub App `softwareschmiede-bot`** (org-installiert; App-ID + Installation-ID). Permissions: Contents / Issues / Pull requests RW, **Administration RW** (Repo-Anlegen **+** Branch-Protection = das PR+Gate), Actions / Workflows / Secrets RW, **Organization → Projects RW** (`createProjectV2` = Auto-Boards). **Warum App statt PAT:** ein Fine-grained-PAT darf `createProjectV2` NICHT (keine org-Boards), eine App schon — plus org-scoped + kurzlebige Tokens.
- **Auth-Mechanik = kurzlebige Installation-Tokens, umgebungs-uniform (Mac == VPS).** App-**Private-Key (base64) + App-ID + Installation-ID** liegen GPG-symmetrisch in der factory-eigenen `.env.gpg`. `scripts/gh-app-token.sh` signiert einen JWT (RS256) → tauscht ihn gegen einen **~1h-Installation-Token**; `source scripts/load-env.sh` → `export GH_TOKEN`; `gh` + API lesen ihn automatisch. Kein langlebiger Token (bei Leak in ~1h tot). GPG-Passphrase via Datei-Chain + Bitwarden; einmal je Box `gh auth setup-git`.
- **Org anlegen ist manuell** (GitHub-UI). **Repos *und* Boards** legt die App danach selbst an.
- **Projects v2** für Boards (Kanban + Iteration/Sprint + Roadmap), Org-Ebene.
- **Deploy/Registry:** Default `deploy: docker` (profil-überschreibbar auf `static|package|none`). CI baut bei Push auf `main` ein Image und pusht nach **ghcr.io** (`ghcr.io/<org>/<name>`) via eingebautem `GITHUB_TOKEN` (`packages: write`) — **kein Push-Secret nötig**. Actions: kostenlose Freiminuten oder self-hosted Runner auf dem VPS. Das tatsächliche Deployen (Pull+Run) + die Live-Preview-URLs sind in **§8a** spezifiziert.

## 8a. Deploy, Live-Preview & URLs (self-hosted, Cloudflare)

**Grundprinzip:** Nach `/flow` (Merge → CI baut Image → `ghcr.io/<org>/<app>:latest`) wird das **produktive Image** als Container gestartet — **dort, wo `/flow` läuft** — und bekommt eine Test-URL.

- **`/flow` auf dem Mac:** `docker pull ghcr…/<app>` → `docker run` lokal → **`http://localhost:<port>`**. Kein Cloudflare nötig.
- **`/flow` auf dem VPS:** dito in den VPS-Docker → zusätzlich Cloudflare-Route → **`https://<app>.alexstuder.cloud`** (von überall erreichbar).

Wo der Container landet, folgt der Arbeitsmaschine (Mac-App → Mac-Docker, VPS-App → VPS-Docker). Eine App lebt an **genau einem** Ort → kein Hostname-Konflikt.

**Zwei Arten URL:**

| Name | Zweck | Technik |
|---|---|---|
| `dev.alexstuder.cloud` | **SSH/Terminal** zum *aktuellen* VPS (Termius) | DNS → VPS (kein App-Tunnel) |
| `<app>.alexstuder.cloud` | **HTTP-Live-Preview** einer auf dem VPS deployten App | Cloudflare-Tunnel → Container |

→ pro App eine eigene Subdomain (mehrere Apps koexistieren); Mac-Apps bleiben auf `localhost:<port>`.

**`dev` (SSH, migrierbar) — entschieden: A-Record.** `dev.alexstuder.cloud` = **A-Record (DNS-only/grau) → öffentliche VPS-IP**, normales SSH:22 (Termius ohne Client-Setup). Der **Bootstrap upsert**et den Record beim Aufsetzen via Cloudflare-API → Migration = neuen VPS bootstrappen, Record zeigt automatisch um, alter VPS weg. **Härtung im Bootstrap: key-only Login + fail2ban** (SSH-Port ist offen). *(Spätere Härtungs-Option: SSH durch den Tunnel via `cloudflared access ssh` = kein offener Port, dafür Termius-ProxyCommand.)*

**App-Preview (HTTP):** Der VPS fährt **einen Cloudflare-Named-Tunnel** (Bootstrap legt ihn via API an). Pro deployter App: Ingress-Regel `<app>.alexstuder.cloud → http://localhost:<port>` + DNS-CNAME → Tunnel; TLS macht Cloudflare. `/flow` (VPS-Rolle) hängt die Route beim **ersten** Deploy an und ersetzt bei Folgeläufen nur den Container (gleicher Port → Route bleibt gültig). **Bei VPS-Migration werden App-Previews NICHT mit-gezügelt** (nur `dev` zieht um, s.o.): Previews sind on-demand (s. *Lifecycle & Cleanup*) und entstehen erst neu, wenn du auf dem neuen VPS eine App deployst — die `<app>.`-Route/CNAME wird dann frisch angelegt.

**Wie `/flow` Mac vs VPS unterscheidet:** der **Bootstrap (VPS-Pfad)** schreibt eine Rolle-Markierung (`DEPLOY_ROLE=vps` + `PREVIEW_DOMAIN=alexstuder.cloud` in die factory-`.env` bzw. `/etc/softwareschmiede/role`). Fehlt sie (Mac) → `local` → nur `localhost`. `/flow` liest das im Deploy-Schritt.

**Per-App-State:** Host-Port in `.claude/profile.md` (`preview_port`), beim ersten Deploy vergeben (erste freie). Container-Name = `<app>`; Lifecycle `docker rm -f <app>; docker run -d --name <app> --restart unless-stopped -p <port>:<cport> ghcr…/<app>:latest`.

**Cloudflare-Zugang:** `CLOUDFLARE_API_TOKEN` + `_ACCOUNT_ID` + `_ZONE_ID` (aus dem Brewing-Setup übernommen) liegen in der factory-`.env.gpg`; Bootstrap/`/flow` nutzen sie für DNS + Tunnel-Routen.

**Lifecycle & Cleanup (Preview ist wegwerfbar):** **Source of Truth = das ghcr-Image** (bleibt dauerhaft in GitHub). Container, lokales Image und Cloudflare-Eintrag sind **ephemer** — jederzeit aus ghcr neu erzeugbar, müssen also weder dauerhaft laufen noch eine Migration überleben. Eine Preview lebt **bis zum expliziten Teardown** (Default: **manuell** — Neuaufbau aus ghcr ist billig). Dafür ein `preview`-Skill:
- **`/preview up <app>`** — ghcr-Image pullen + Container starten (+ VPS: Route/CNAME anlegen) → URL. (Genau das macht auch `/flow` am Ende automatisch.)
- **`/preview down <app>`** (Cleanup) — `docker rm -f <app>` + (VPS) `<app>`-Ingress-Regel + DNS-CNAME via API entfernen + optional `docker rmi` (lokales Image prunen). **ghcr-Image, Repo und Board werden NIE angefasst.**
- **`/preview list`** — aktive Previews (Container + Routen).
- **`/preview up <app>`** (repo-unabhängig) — Image per Namen `ghcr.io/<org>/<app>` laden ohne ins Repo zu wechseln; `container_port` per `docker inspect` aus dem Image abgeleitet.
- **`/preview available`** — Menü der previewbaren Apps (Org-Repos außer `agent-flow`) für `up <app>`.

*(Optionaler Reaper später: Previews, die > N Tage idle sind, automatisch abräumen — weil aus ghcr trivial wiederherstellbar.)*

**Abgrenzung zum Brewing-Tunnel:** `alexstuder.cloud` ist auch Brewing-Staging. Die Softwareschmiede nutzt **dieselbe Zone**, aber **eigene Subdomains** (`dev.`, `<app>.`) und einen **eigenen Tunnel** auf ihrem VPS — Brewing-Records werden nie angefasst (`/flow` legt nur `<app>.`-Records an, der Bootstrap nur `dev.` + Tunnel).

**Reihenfolge:** Die **Mac-Seite** (Pull + lokaler Run + `localhost`-URL) ist **ohne VPS testbar** und kommt zuerst; die VPS-/Cloudflare-Seite (Bootstrap-Tunnel, `<app>.`-Routen, `dev`-DNS) wird gebaut, sobald ein VPS existiert.

## 9. Explizit NICHT im Scope (bewusst)

- Keine headless/unattended Ausführung über die API; keine nächtlichen Cron-Agenten; kein Agent-SDK/Runner. (Alles interaktiv.)
- Kein projekt-/sprach-spezifischer Inhalt im Plugin-Repo selbst.

## 10. Verhältnis zum Brewing-Projekt

Komplett **getrennt**. Das Brewing-Projekt (`WebPageNew/*`) wird **nicht angefasst**; seine bespoke Agenten
laufen unverändert weiter. Optionale, *spätere* Migration: Brewing konsumiert das Plugin + ein Brewing-Profil —
erst wenn das Framework an einem Wegwerf-Projekt bewiesen ist.

## 11. Entscheidungen & nächste Arbeit

**Entschieden:** Org-Name `Studis-Softwareschmiede` + Repo-Arbeitstitel `agent-flow`; GitHub-Zugang via **GitHub App `softwareschmiede-bot`** (App-Key+IDs in `.env.gpg`, kurzlebige Token via JWT-Mint). Bitwarden hält `studis-softwareschmiede-gpg-passphrase` + `studis-softwareschmiede-github-app` (Felder app_id/installation_id/private_key_b64) + optional `studis-softwareschmiede-claude-token`. *(Der frühere Fine-grained-PAT `studis-softwareschmiede-github-token` wurde durch die App abgelöst und **revoked**.)* Gate-Stufe = `reviewer`-Check + Mensch-Approve; Tester = Build+Smoke (profil-erweiterbar); Board = Task-Queue-Pipeline (siehe §4a). **Deploy/Preview (§8a):** Container folgt der Arbeitsmaschine (Mac→`localhost`, VPS→`<app>.alexstuder.cloud`); `dev.alexstuder.cloud` = SSH-DNS zum aktuellen VPS (migrierbar via Bootstrap-Upsert). Cloudflare-Creds (`API_TOKEN`/`ACCOUNT_ID`/`ZONE_ID`) aus dem Brewing-Setup in die factory-`.env.gpg` übernommen. `dev`-SSH = **A-Record→VPS-IP** (gehärtet, kein Tunnel); Preview-**TTL = manuell** (`/preview down`; Reaper später); **ghcr-Image = Source of Truth** (Cleanup lässt es unangetastet).

**Entschieden (Spec-getriebene Doku, §4d):** Entwicklung läuft **Konzept → Detailkonzept → Spezifikation → Code**; die drei Doc-Schichten sind durable, sprach-neutrale **Source of Truth**. (1) Ort = **`docs/` im App-Repo** (beim Port geseedet); (2) **3 Schichten** `concept.md` / `architecture.md` / `specs/`; (3) **hartes Drift-Gate** (reviewer blockt Verhaltensänderung ohne Spec-Delta, Code+Spec im selben PR); (4) **Hybrid-Authoring** (requirement legt Specs an, coder darf kleine Lücken nachziehen, Strukturelles → zurück an requirement); (5) **eigener Reverse-Eng-Schritt** „Spec aus Code ableiten" (via `/init`, mensch-validiert) → macht auch Bestands-Apps portierbar. Bewusst **anders als die Brewing-Konvention** (dort Specs transient/gitignored): in der Fabrik ist nur das Q&A flüchtig, der Spec-Output durable.

**Entschieden (Stufe-1-Traceability):** (1) **Use-Case-2.0-Hybrid** im Spec-Template — Main/Alternative Flows optional als Herleitung, Acceptance-Kriterien bleiben der Pflicht-Vertrag (keine Pre-/Postconditions als Pflichtfelder). (2) **Geschäftsregeln `BR-NNN`** leben zentral in `architecture.md` (Verhalten) / `data-model.md` (Validierung + Enforcement-Layer), kein eigenes File; Specs referenzieren, Tests taggen. Namensraum getrennt von Fabrik-Regeln `lang/R<NN>`. (3) **Spec↔Test-Traceability**: sprach-neutraler Vertrag (`docs/architecture/traceability-subsystem.md`) + idiomatisches Tagging je Pack (`## Spec-Tagging`) + abgeleitete Map; `tester` rechnet hartes Coverage-Gate (jede genannte AC + referenzierte BR ≥ 1 deckender Test).

**Noch zu erarbeiten (vor Scaffold):**
1. **Agenten im Detail** — je Agent (`requirement, coder, reviewer, tester, retro, train`): genaue Aufgabe, Input/Output-Format, Tools, Lese-Pflichten (Profil/Lessons), harte Grenzen — generisch & sprach-neutral.
2. **`/flow` im Detail** — Schritt-für-Schritt-Orchestrierung: Board lesen → Reihenfolge/Item-Auswahl → Handoffs → Status-Updates → Blocked/Resume → Done-Verlinkung.
3. (Platz für Punkte, die beim Detaillieren auftauchen.)

## 12. Phasen-Plan

- **P1 — Scaffold:** Plugin-Skelett (manifest, marketplace, generische `coder/reviewer/tester`, `/flow`-Skill, per-Projekt-Profil/Lessons-Mechanik). Lokal, neues Repo.
- **P1b — Spec-getriebene Doku (§4d):** `templates/_docs/` (concept/architecture/spec/glossary-Skelett, sprach-neutral) + `new-project` scaffoldet `docs/`; `requirement` schreibt durable Specs + Board referenziert Spec-IDs; `coder`/`reviewer`/`tester` auf Spec-als-Quelle umstellen (reviewer: hartes Drift-Gate); `/init` „Spec-aus-Code"-Schritt; Port = `docs/` seeden + Profil tauschen. Zieht durch P1/P3 (Templates + `new-project`/`init`).
- **P2 — Self-Improvement:** `retro` + `train` als PR-erzeugende Skills + Branch-Protection/Gate.
- **P3 — GitHub-Integration:** `new-project`-Skill (Repo + Board + Profil bootstrappen), Deploy-Template (Actions).
- **P4 — Beweisen:** Wegwerf-Projekt end-to-end (`/flow` → PASS → tester → deploy → Board).
- **P5 — Live-Preview & Cloudflare (§8a):** (a) **Mac-Seite zuerst** — `/flow`-Deploy-Schritt: produktives ghcr-Image pullen + lokal `docker run` + `localhost`-URL (ohne VPS testbar) + **`/preview up|down|list`**-Skill (Cleanup: Container + lokales Image + Cloudflare-Eintrag weg, ghcr-Image bleibt). (b) **VPS-Seite** (sobald VPS da): Bootstrap installiert cloudflared + Named-Tunnel + `dev`-DNS-Upsert + Rolle-Marker; `/flow`/`preview up` (VPS-Rolle) legt pro App `<app>.alexstuder.cloud`-Route+CNAME an, `preview down` entfernt sie wieder.
- **P6 — optional:** Brewing migrieren.
