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

## 3. Eine Ebene, kein Cloud-Plane

```
INTERAKTIV (du am Keyboard, Claude-Code unter Abo)
  /flow <task>   → coder → reviewer ⇄ Loop (bis Review-Gate: PASS) → tester → fertig
  /retro         → Retro-Agent: gesammelte Lessons → Skill-Verbesserung (als PR)
  /train <lang>  → Training-Agent: Web-Recherche neuer Patterns → Skill-/Profil-Update (als PR)

GITHUB (kostenlos, ohne Claude)
  Push → Actions → Build + Deploy        |   Projects v2 → Kanban/Scrum-Board pro Projekt
```

Beide Meta-Agenten (Retro/Train) und der Kern-Loop nutzen **dieselben** versionierten Agent-Skills.

## 4. Die Agenten

Generisch + **sprach-adaptiv** (kein per-Sprache-Agent; stattdessen ein neutraler Agent + per-Projekt-/
per-Sprache-Wissen, das er zur Laufzeit liest). Sprach-Spezifika kommen aus dem Projekt-Profil und den
vom Training-Agent gepflegten Sprach-Wissensdateien.

- **requirement** — verfeinert eine vage Anforderung in eindeutige, eigenständig umsetzbare TODOs und schreibt sie priorisiert aufs Board (Front-of-Funnel). Fragt **iterativ in Runden von max. 2–3 Fragen** nach, bis die Anforderung eindeutig UND in kleine Pakete zerlegbar ist. Schreibt KEINEN Code.
- **architekt** (Design) — definiert die App-Architektur (Struktur/Komponenten/Layer/Tech) → bindende `.claude/architecture.md`. Kein Code.
- **dba** (Design) — erarbeitet das Datenmodell (Entitäten/Relationen/RLS-Konzept) → bindende `.claude/data-model.md`; der `coder` implementiert es. Kein Code/keine Migrationen.
- **designer** (Design, optional/UI) — definiert Design-System + UX/Visual-Vorgaben (Palette/Spacing/Typo/Komponenten/A11y) → bindende `.claude/design.md`. Kein Code. Design-Review macht der `reviewer` via UI-Pack-Checklist (kein eigener Design-Reviewer).
- **coder** — implementiert eine Aufgabe; liest Projekt-Kontext + Lessons + Profil + Design-Docs; testet selbst; übergibt zum Review.
- **reviewer** — prüft, kategorisiert `Critical / Important / Suggestions`, gibt `Review-Gate: PASS | CHANGES-REQUIRED`. Critical+Important sind der Arbeitsauftrag zurück an den coder.
- **tester** — der Abschluss nach Review-PASS: **Default „Build + Smoke"**, pro Projekt-Profil auf echte Test-Suite/E2E erweiterbar; eigenes Gate.
- **retro** (Meta) — destilliert die gesammelten Lessons-learned in Verbesserungen der Agent-Skills. Schreibt als **PR**.
- **train** (Meta) — recherchiert im Netz aktuelle Patterns/Best-Practices je Sprache, fließt in Skills/Sprach-Profile ein. Schreibt als **PR**.
- **teamLeader** (Meta, *später*) — gliedert einen NEUEN Agenten ins Team + den Workflow ein (Spec + Verdrahtung in Handoff-Kette/Skills), via **PR+Gate**. Selbst-Erweiterung der Fabrik; nicht P1.

### Kern-Loop (aus dem Brewing-Projekt übernommen, hier generisch)
coder finished → Handoff → reviewer → bei `CHANGES-REQUIRED`: Critical+Important zurück → fix → erneut →
bis `PASS` → tester. **Schleifen-Schutz:** derselbe Befund überlebt max. 3 Iterationen, dann Abbruch + Vorlage an den User.

## 4a. Pipeline: requirement → Board → /flow (der Betrieb)

Das GitHub-Board ist nicht nur Anzeige, sondern **Arbeits-Queue UND persistenter Zustand**:

**Vorgelagert (Design):** `architekt` (+ `dba` bei DB-Domäne) erzeugen die bindenden Design-Docs `.claude/architecture.md` / `.claude/data-model.md`, *bevor* `requirement` zerlegt — `coder`/`reviewer` behandeln sie als Constraints.

1. **`requirement`-Agent** verfeinert die Anforderung in einzelne, eigenständig umsetzbare TODOs und schreibt sie als Items aufs Board (Spalte **To Do**) — mit **Reihenfolge/Priority** und notierten harten Abhängigkeiten („braucht #3").
2. **`/flow` (Orchestrator = die interaktive Haupt-Session)** liest das Board (To Do, in Reihenfolge) und arbeitet **Punkt für Punkt**:
   - Item → **In Progress** → `coder → reviewer ⇄ Loop → tester` → bei PASS → **Done** (+ PR/Commit ans Item verlinkt) → nächstes Item.
   - Kommt ein Item nicht durch (3-Iterationen-Schleifenschutz) → **Blocked**, Meldung an den User, Rückfrage ob mit den restlichen Items weiter.
3. **Interaktiv:** der User triggert `/flow`, kann zwischen Items eingreifen, stoppen, umpriorisieren. Bricht eine Session ab, zeigt das Board den Stand → jederzeit fortsetzbar.

**Board-Spalten:** `To Do │ In Progress │ Blocked │ In Review │ Done`.

**Defaults:** (1) Reihenfolge via Priority-Feld + Abhängigkeits-Notiz; (2) jedes Item ≈ ein coder→reviewer→tester-Durchlauf (Slicing ist `requirement`-Aufgabe); (3) Fehlschlag → Blocked + Rückfrage; (4) bei Done PR/Commit ans Item hängen.

## 4b. /flow-Spine & Handoff-Verträge (akzeptiert)

**Board-Item-Vertrag:** Title + **Acceptance Criteria** (Body) + Priority/Order + optional Depends-on + Status (**nur** der Orchestrator schreibt Status).

**`/flow`-Ablauf** (cwd = Ziel-Projekt-Repo):
0. Board-Ref aus `.claude/profile.md`.
1. Nächstes „To Do" (höchste Priority, dessen Depends-on alle „Done") → **In Progress**. (keins → „Board leer".)
2. LOOP (≤ 3 Iterationen): `coder → reviewer`. CHANGES-REQUIRED → Critical+Important zurück an coder → erneut; PASS → weiter. Schleifenschutz erschöpft → **Blocked** + Kommentar + Meldung an User.
3. `tester` (interaktiv). FAIL → zurück an coder (zählt zum Schutz); PASS → weiter.
4. Code landen gemäß `merge_policy` → Item **Done** (+ PR/Commit verlinkt) → nächstes Item.

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
- **Seed-Packs zu Beginn:** `flutter`, `html`, `css`, `tailwind`, `angular`, `java`, `js`, `sql` (+ `architecture` als Domäne). UI-Frameworks (Angular/Tailwind/CSS/HTML) sind **Packs**, kein eigener Agent.

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

**Tier 2 (später):** `/flow` loggt pro Item Metriken (Iterationen-bis-PASS, #Critical/Important, Test-First-Pass, Blocked) → Trends + GitHub Projects Insights-Charts.

Touchpoints: `reviewer` (Regel-ID-Tagging), `retro`/`train` (Ledger + Board pflegen).

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
- `.claude/architecture.md` + `.claude/data-model.md` + `.claude/design.md` — **bindende Design-Docs** von `architekt`/`dba`/`designer`; `coder`/`reviewer` behandeln sie als Constraints (Architektur-/Modell-/Design-Konformität = Review-Kriterium).
- `.claude/lessons/{coder,reviewer,tester}.md` — **projekt-isolierte** Lessons (Reviewer schreibt hierhin, coder liest). Kein Cross-Contamination, Fabrik bleibt sauber.
- GitHub **Project (v2)** — eigenes Kanban/Scrum-Board pro Projekt (Status-Board + Iteration-Felder für Sprints); via `gh project`/GraphQL automatisierbar.

**Woher diese Dateien kommen:** der `new-project`-Skill (Neuanlage) bzw. `init` (bestehendes Repo adoptieren) erzeugt sie beim **Bootstrap** aus `templates/<lang>/`: Repo + Board v2 anlegen, Stack erkennen → `profile.md` (Build/Test/Lint/Smoke, `merge_policy: pr`, Board-Ref, `deploy: docker` [profil-überschreibbar], `image: ghcr.io/<org>/<name>`, `registry: ghcr`), minimale `CLAUDE.md` (Template + 1–2 Rückfragen), leere `lessons/*`, plus **`Dockerfile` + CI-Workflow** (Build → Push nach ghcr.io via eingebautem `GITHUB_TOKEN`) und **Branch-Protection** (require PR + `reviewer`-Check; solo: kein Pflicht-Human-Approval, du mergst selbst). `requirement` *konsumiert* das nur. **Lifecycle: `new-project`/`init` → `requirement` → `/flow`.** **Stack-Entscheidung:** finale Wahl beim User; `architekt` berät/schlägt vor, wenn nicht vorgegeben; `init` erkennt aus dem Code; sie lebt in `profile.md` und steuert Pack-Laden/Templates/Design-+DBA-Aktivierung. Detail-Spec: `AGENTS.md`.

## 8. GitHub-Integration

- **Voller GitHub-Zugang via GitHub App `softwareschmiede-bot`** (org-installiert; App-ID + Installation-ID). Permissions: Contents / Issues / Pull requests RW, **Administration RW** (Repo-Anlegen **+** Branch-Protection = das PR+Gate), Actions / Workflows / Secrets RW, **Organization → Projects RW** (`createProjectV2` = Auto-Boards). **Warum App statt PAT:** ein Fine-grained-PAT darf `createProjectV2` NICHT (keine org-Boards), eine App schon — plus org-scoped + kurzlebige Tokens.
- **Auth-Mechanik = kurzlebige Installation-Tokens, umgebungs-uniform (Mac == VPS).** App-**Private-Key (base64) + App-ID + Installation-ID** liegen GPG-symmetrisch in der factory-eigenen `.env.gpg`. `scripts/gh-app-token.sh` signiert einen JWT (RS256) → tauscht ihn gegen einen **~1h-Installation-Token**; `source scripts/load-env.sh` → `export GH_TOKEN`; `gh` + API lesen ihn automatisch. Kein langlebiger Token (bei Leak in ~1h tot). GPG-Passphrase via Datei-Chain + Bitwarden; einmal je Box `gh auth setup-git`.
- **Org anlegen ist manuell** (GitHub-UI). **Repos *und* Boards** legt die App danach selbst an.
- **Projects v2** für Boards (Kanban + Iteration/Sprint + Roadmap), Org-Ebene.
- **Deploy/Registry:** Default `deploy: docker` (profil-überschreibbar auf `static|package|none`). CI baut bei Push auf `main` ein Image und pusht nach **ghcr.io** (`ghcr.io/<org>/<name>`) via eingebautem `GITHUB_TOKEN` (`packages: write`) — **kein Push-Secret nötig**. Actions: kostenlose Freiminuten oder self-hosted Runner auf dem VPS. Das tatsächliche Deployen (Pull+Run, Watchtower-Stil) ist ein separater per-Projekt-Schritt (späteres Template).

## 9. Explizit NICHT im Scope (bewusst)

- Keine headless/unattended Ausführung über die API; keine nächtlichen Cron-Agenten; kein Agent-SDK/Runner. (Alles interaktiv.)
- Kein projekt-/sprach-spezifischer Inhalt im Plugin-Repo selbst.

## 10. Verhältnis zum Brewing-Projekt

Komplett **getrennt**. Das Brewing-Projekt (`WebPageNew/*`) wird **nicht angefasst**; seine bespoke Agenten
laufen unverändert weiter. Optionale, *spätere* Migration: Brewing konsumiert das Plugin + ein Brewing-Profil —
erst wenn das Framework an einem Wegwerf-Projekt bewiesen ist.

## 11. Entscheidungen & nächste Arbeit

**Entschieden:** Org-Name `Studis-Softwareschmiede` + Repo-Arbeitstitel `agent-flow`; GitHub-Zugang via **GitHub App `softwareschmiede-bot`** (App-Key+IDs in `.env.gpg`, kurzlebige Token via JWT-Mint). Bitwarden hält `studis-softwareschmiede-gpg-passphrase` + `studis-softwareschmiede-github-app` (Felder app_id/installation_id/private_key_b64) + optional `studis-softwareschmiede-claude-token`. *(Der frühere Fine-grained-PAT `studis-softwareschmiede-github-token` wurde durch die App abgelöst und **revoked**.)* Gate-Stufe = `reviewer`-Check + Mensch-Approve; Tester = Build+Smoke (profil-erweiterbar); Board = Task-Queue-Pipeline (siehe §4a).

**Noch zu erarbeiten (vor Scaffold):**
1. **Agenten im Detail** — je Agent (`requirement, coder, reviewer, tester, retro, train`): genaue Aufgabe, Input/Output-Format, Tools, Lese-Pflichten (Profil/Lessons), harte Grenzen — generisch & sprach-neutral.
2. **`/flow` im Detail** — Schritt-für-Schritt-Orchestrierung: Board lesen → Reihenfolge/Item-Auswahl → Handoffs → Status-Updates → Blocked/Resume → Done-Verlinkung.
3. (Platz für Punkte, die beim Detaillieren auftauchen.)

## 12. Phasen-Plan

- **P1 — Scaffold:** Plugin-Skelett (manifest, marketplace, generische `coder/reviewer/tester`, `/flow`-Skill, per-Projekt-Profil/Lessons-Mechanik). Lokal, neues Repo.
- **P2 — Self-Improvement:** `retro` + `train` als PR-erzeugende Skills + Branch-Protection/Gate.
- **P3 — GitHub-Integration:** `new-project`-Skill (Repo + Board + Profil bootstrappen), Deploy-Template (Actions).
- **P4 — Beweisen:** Wegwerf-Projekt end-to-end (`/flow` → PASS → tester → deploy → Board).
- **P5 — optional:** Brewing migrieren.
