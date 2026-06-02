# Architecture — Upgrade-Subsystem (`/upgrade`, autonomer Stack-Modernisierer)

> **Bindend.** Diese Spec beschreibt **wie** das `agent-flow`-Plugin ein bestehendes Projekt-Repo **autonom** auf den neuesten, kompatiblen, sichersten und funktionierenden Stand hebt: Ist-Versionen erkennen → neueste recherchieren → **Cross-Achsen-Kompatibilität** auflösen → **UpgradePlan** als Spec + Board-Items → Stufe für Stufe via `/flow` ausführen → Wissenslücken via `train --bootstrap` schließen → testen + Loop → `retro`. Sie baut additiv auf den vier Achsen (`language` / `db_dialect` / `frameworks`+`build` / `db_migration_tool`) auf. Sie **erweitert** den Single-Writer-Vertrag (CONCEPT §4b) minimal und begründet (§3/§7), bricht sonst **keine** bestehenden Handoff-Verträge. Implementierung erfolgt in sechs Wellen (§15). Abweichungen sind Review-Kriterium.

---

## 1. Zweck & Scope

**Zweck.** Heute kann die Fabrik ein Repo *adoptieren* (`/adopt`) und Items *abarbeiten* (`/flow`), aber das **Modernisieren eines Bestands-Stacks** (Sprache + Frameworks + Build + DB-Migrations-Tool von alt auf aktuell) ist ein manueller, fehleranfälliger Mehr-Schritt-Marathon — wir haben ihn für Angular 13→21, Spring Boot 3→4 und Java→25 in der Pack-Vorbereitung von Hand durchexerziert. `/upgrade` automatisiert genau diesen bewährten Ablauf end-to-end.

**Kern-Eigenschaft: Voll-Autonomie.** Ein Upgrade über viele Major-Stufen dauert lange; `/upgrade` ist darauf ausgelegt, **ohne menschliche Zwischeneingriffe** durchzulaufen (z.B. über Nacht). Das verlangt drei Dinge, die diese Spec liefert: (a) ein **hermetisches Pack-Loading** (§10), das die `/reload-plugins`-Barriere eliminiert; (b) **Failure-Isolation + Resume** (§11), damit eine rote Stufe nicht den ganzen Lauf killt; (c) einen **deterministischen Kompatibilitäts-Solver** (§6), damit die Reihenfolge der Bumps konfliktfrei ist.

**Verhältnis zu CONCEPT §9 (Autonomie-Posten).** CONCEPT §9 schließt „headless/unattended über die **API**" und „nächtliche **Cron**-Agenten" aus. `/upgrade` verletzt das NICHT: Es läuft als **eine lange, interaktiv gestartete Claude-Code-Session** (Abo-gedeckt, kein API-Per-Token, kein Cron, kein Agent-SDK). „Autonom" heißt hier **eingaben-frei innerhalb eines Laufs**, nicht „API-headless". Der Lauf wird vom Menschen gestartet und kann jederzeit unterbrochen + via Board/Profil wieder aufgesetzt werden (§11).

**Zwei-Repo-Natur (zentral).** `/upgrade` arbeitet gleichzeitig in:
- dem **Ziel-Projekt-Repo** (cwd) — hier passiert der eigentliche Upgrade (Code, `docs/specs/`, Board, PRs pro Stufe), gefahren durch `/flow`.
- dem **agent-flow-Source-Repo** — hier werden fehlende Knowledge-Packs via `train --bootstrap` erzeugt (PR gegen `main`, Durability).

Diese beiden Spuren sind entkoppelt: Der autonome Lauf wird durch Fabrik-PRs **nicht blockiert** (§10).

**Out of Scope (P1).**
- **Sprung über mehrere Majors in einem Schritt.** `/upgrade` geht je Achse **eine Major-Stufe nach der anderen** (Leiter, §7) — niemals 13→21 direkt. Das ist die einzige sichere, gegate-bare Form.
- **Auto-Merge von Fabrik-Änderungen.** `train --bootstrap`-PRs gegen agent-flow werden NIE vom autonomen Lauf gemergt — Mensch reviewt/merged später (§5 Gate bleibt). Der Lauf nutzt das Pack lokal aus dem Staging-Dir (§10).
- **Cross-Achsen-Auto-Konvertierung** (z.B. Tool-Wechsel Flyway→Prisma). `/upgrade` hebt Versionen, wechselt aber nicht das Tool/Framework (analog `migration-tool-subsystem.md` §1 Out-of-Scope).
- **Downgrade / Pinning auf nicht-neueste Versionen** außer wenn der Solver es als Kompatibilitäts-Auflösung erzwingt.
- **Frameworks ersetzen** (z.B. AngularJS→React). Reine Versions-Modernisierung derselben Technologie.

---

## 2. Begriffe & Achsen

`/upgrade` operiert auf den vier bestehenden Profil-Achsen plus einer neuen Hilfsachse:

| Achse | Profil-Feld | Versions-Träger | Pack-Quelle |
|---|---|---|---|
| Sprache | `language` | Tag-versioniert (`since:`) | `knowledge/<language>.md` |
| Framework | `frameworks: ["<id>@<major>"]` | Cut pro Major | `knowledge/frameworks/<id>-<major>.md` |
| Build-Tool | `build` | i.d.R. Tag | `knowledge/build/<id>.md` |
| DB-Dialekt | `db_dialect` | stabil | `knowledge/<dialect>.md` |
| DB-Migrations-Tool | `db_migration_tool` | Cut bei Bedarf | `knowledge/migration/<tool>[-<major>].md` |
| **Container-Runtime** (NEU, §13) | `container_runtime` | — | wird von Framework-Constraints referenziert (z.B. Servlet 6.1 schließt Undertow aus) |

**Ziel-Zustand.** `/upgrade` berechnet pro Achse eine **Ziel-Version** und schreibt sie nach Abschluss zurück ins `profile` (`angular@13`→`angular@21`, `db_migration_tool: flyway@9`→`flyway@10`, …). Bis dahin lebt der Ziel-Zustand im `upgrade`-Block des Profils (§13) als Fortschritts-Marker.

> **Namens-Hinweis (Profil-Feld Sprache).** Diese Spec verwendet durchgängig `language` (so heißt das Feld in den realen `templates/*/profile.md` und in `AGENTS.md` „Gemeinsamer Kontext", die der `coder` zur Laufzeit liest). `docs/architecture/framework-build-subsystem.md` benutzt stellenweise `lang` — eine **bestehende Doku-Drift**, deren Harmonisierung außerhalb dieser Spec liegt (eigener Cleanup). Wo unten `<language>` im Pfad steht, ist der **Wert** des Felds gemeint (z.B. `knowledge/java.md`).

---

## 3. Die `/upgrade`-Pipeline (Überblick)

```
/upgrade [<owner/repo>]        (cwd = Ziel-Projekt-Repo; <owner/repo> optional, sonst cwd)

 A Detect    Ist-Versionen je Achse aus dem Repo + profile lesen
 B Research  pro Achse die neueste/empfohlene Version aus Primärquellen ermitteln
 C Solve     Cross-Achsen-Kompatibilität auflösen → konsistentes Ziel-Set + Bump-Reihenfolge
 D Plan      docs/specs/upgrade-<datum>.md (AC je Stufe) + Board-Items als Leiter (Depends-on)
 E Gaps      fehlende Knowledge-Packs via train --bootstrap erzeugen (Staging-Dir + PR)
 F Execute   /flow arbeitet die Leiter ab (coder→reviewer⇄→tester je Stufe) → Tests → retro
```

`/upgrade` ist ein **Orchestrator-Skill**, kein neuer Loop: Phase F ruft das bestehende `/flow` (CONCEPT §4b). `/upgrade` legt initial **die UpgradePlan-Spec (Commit) + die Board-Items** an und schreibt am Ende die erreichten Ziel-Versionen ins `profile` zurück — eine **bewusste, begründete Erweiterung** des Single-Writer-Vertrags (bisher nur `/flow` schreibt Board/git), strukturell analog dazu, dass `requirement` Items in „To Do" anlegt. **Alle Item-Status-Übergänge (To Do→…→Done) und alle Code-PRs pro Stufe bleiben ausschließlich `/flow`-Hoheit.** Welle 6 trägt diese Erweiterung in CONCEPT §4b / `AGENTS.md` nach.

---

## 4. Phase A — Detect

Wiederverwendung der `/adopt`-Detection-Heuristiken (`framework-build-subsystem.md` §6, `migration-tool-subsystem.md` §6) — keine neue Erkennungslogik.

1. **Voraussetzung:** Repo ist adoptiert (`.claude/profile.md` existiert, `adoption_validated_at != null`). Fehlt das → `/upgrade` stoppt mit Hinweis „erst `/adopt` ausführen".
2. **Ist-Versionen lesen** je Achse: `profile.language` (+ konkrete JDK/Node-Version aus `pom.xml`/`.nvmrc`/Toolchain), `profile.frameworks[]`, `profile.build`, `profile.db_dialect`, `profile.db_migration_tool`. Genaue Patch-Stände aus den Dependency-Koordinaten (`pom.xml`, `package.json`, `build.gradle`).
3. **Ergebnis:** `current[]` — eine Map Achse→Ist-Version, geloggt im Lauf-Report.

---

## 5. Phase B — Research (neueste Versionen)

Pro Achse die **neueste stabile + empfohlene** Version ermitteln, mit der **train-Quellen-Disziplin** (`agents/train.md`: nur `primary_sources`, `non_sources` verboten, verbatim-Belege, Preview ≠ stable).

- Sprache: neueste **LTS** (nicht zwingend neueste Release) — z.B. Java 25, Node 22 LTS.
- Framework/Build/Migration-Tool: neueste Major-GA.
- DB-Dialekt: neueste stabile Server-Version (selten Treiber der Modernisierung, aber als Constraint relevant).

**Ergebnis:** `latest[]` — Achse→Kandidaten-Ziel + Quell-Links. Diese Kandidaten gehen in den Solver (§6), nicht ungeprüft ins Ziel-Set.

---

## 6. Phase C — Kompatibilitäts-Solver (Kern)

**Problem.** „Neueste je Achse" ist oft inkonsistent: Ziel-Flyway braucht ggf. ein höheres Java als Ziel-Spring vorgibt; ein Framework schließt eine Container-Runtime aus. Der Solver löst das deterministisch auf.

**Datengrundlage (Entscheidung: Header-Felder + Web-Fallback).**
1. **Maschinenlesbare Constraints** aus den Pack-Headern (Schema §12 / `framework-build-subsystem.md`): `requires:`, `compatible_with:`, `incompatible:`. Erste Quelle, reproduzierbar, auditierbar.
2. **Web-Fallback** für Ziel-Versionen, deren Pack (noch) keine Constraints führt (typisch bei brandneuen Majors): Live-Recherche aus Primärquellen mit train-Disziplin. Gefundene Constraints werden **zugleich als Pack-Header-Patch vorgeschlagen** und fließen in Phase E (Bootstrap des fehlenden Packs).

**Algorithmus (Constraint-Resolution, kein Voll-SAT nötig).**
```
Eingabe:  candidates[] (aus B) + current[] (aus A)
1. Sammle für jedes Kandidaten-Ziel alle requires/compatible_with/incompatible (Pack-Header
   oder Web-Fallback), transitiv.
2. Erkenne Konflikte:
   - Versions-Floor-Konflikt: z.B. spring-boot@4 requires java>=17 und (hypothetisch) flyway@11 requires java>=21
   - Ausschluss: incompatible: container=undertow gegen profile.container_runtime=undertow
3. Auflösung (Anheben statt Abbrechen):
   - Floor-Konflikt → gemeinsames Maximum der Mindest-Anforderungen wählen, sofern es eine
     unterstützte LTS/Major gibt (z.B. java-Ziel auf 21/25 anheben). Begründung protokollieren.
   - Ausschluss → Konflikt-Achse auf eine kompatible Alternative heben, sofern der Scope (§1)
     das erlaubt (z.B. Undertow→Tomcat ist Runtime-Wechsel innerhalb derselben Framework-Tech: erlaubt;
     Framework-Wechsel: NICHT erlaubt → Konflikt bleibt → Stufe wird als BLOCKED geplant, §11).
4. Reihenfolge bestimmen (topologisch nach requires):
   Sprache → Build-Tool → Framework (Leiter über Majors) → Migrations-Tool → DB.
Ausgabe:  target[] (konsistentes Ziel-Set) + order[] (Bump-Reihenfolge) + conflicts[] (unlösbar → BLOCKED)
```

**Determinismus-Pflicht.** Bei mehreren gültigen Auflösungen gilt eine feste Präferenz: **neueste LTS** der Sprache > neueste GA des Frameworks > Minimal-Anhebung der übrigen Achsen. Kein Zufall, damit Resume (§11) dasselbe Ergebnis reproduziert.

**Beispiel (illustrativ; konkrete Floors gegen Primärquellen/Pack-Constraints verifizieren).** Ziel SB4 (`java>=17`, Pack `spring-boot-4` existiert) + *angenommen* Flyway 11 verlange `java>=21` (hypothetisch; ein `flyway@11`-Pack würde via `train --bootstrap` in Phase E erst angelegt) ⇒ Solver hebt das Java-Ziel auf 25 (neueste LTS, deckt beide Floors); SB4 `incompatible: container=undertow` ⇒ wenn `container_runtime=undertow`, Anhebung auf Tomcat 11; Reihenfolge: java → maven → spring-boot (3→4-Stufe) → flyway.

---

## 7. Phase D — UpgradePlan (Spec + Board-Items als Leiter)

Der Plan ist **durable** (CONCEPT §4d, hartes Drift-Gate) — keine reine Board-Beschreibung.

1. **Spec schreiben:** `docs/specs/upgrade-<datum>.md` aus `templates/_shared/upgrade-plan.md` (§15). Enthält: Ist→Ziel-Tabelle je Achse, Solver-Begründung (inkl. Quell-Links), und **eine nummerierte Acceptance-Kriterien-Gruppe pro Leiter-Stufe** (z.B. `AC-A1: java auf 21; Build grün`, `AC-A2: java auf 25; Build grün`, `AC-F1: angular 13→14; ng update grün, Tests grün`, …).
2. **Board-Items als Leiter:** ein Item pro Major-Stufe pro Achse, in `order[]`, mit `Depends-on`-Kette (jede Stufe hängt an der vorigen + an Achsen-Vorbedingungen aus dem Solver). Body je Item: `Spec: docs/specs/upgrade-<datum>.md` + `implements: AC-<…>` + `Priority` + `Depends-on`. Label `upgrade` (+ `db` wenn DB-Achse berührt → DBA-Review-Trigger in `/flow` §3.2a).
3. **Gap-Items zuerst:** Stufen, die ein fehlendes Pack brauchen, bekommen ein vorgelagertes Gap-Item (Phase E) als `Depends-on`.

`/upgrade` schreibt den Plan-Commit (Spec) + legt die Items an — das ist der **initiale** direkte Board-/git-Eingriff von `/upgrade`. Die einzigen weiteren `/upgrade`-eigenen Schreib-Operationen sind in Phase F der Status-Folge-Commit (`upgrade.status`) und der Profil-Rückschreib (§9); **alle** Item-Status-Übergänge und Code-PRs bleiben `/flow`-Hoheit.

---

## 8. Phase E — Gap-Closing (`train --bootstrap`)

**Lücke = ein Ziel-Pack existiert nicht** (häufigster Fall: neuer Framework-/Migration-Tool-Major). Heute bricht der Loader hart ab (`framework-build-subsystem.md` §5) und `train` bootstrappt nicht (`agents/train.md`: Resolver-Verhalten „Pack fehlt → STOPP"). Diese Spec erweitert `train` um einen **`--bootstrap`-Modus** (Vertrag in `agents/train.md`, Welle 3):

```
train --bootstrap <pack-id>
1. Pack fehlt → NICHT abbrechen, sondern anlegen:
   - Cut-Pack: Skelett durch Kopie+Anpassung des Vorgänger-Packs (versioning.md "Pack-Anlage-Pflicht"),
     Header neu (framework_version_range, pack_date, primary_sources), Vorgänger bekommt superseded_by.
   - Sektion A aus Primärquellen füllen (normale train-Disziplin), B leer, C vom Vorgänger.
   - requires/compatible_with/incompatible-Header aus den recherchierten Fakten setzen (§12).
2. Schreibt das fertige Pack in ZWEI Ziele:
   (a) den hermetischen Staging-Dir des Laufs (§10) → der Lauf nutzt es SOFORT.
   (b) einen PR gegen agent-flow (Branch `bootstrap/<pack-id>`) → Durability, Mensch-Gate (§5).
3. Mergt den PR NICHT (Out-of-Scope §1).
```

**Abgrenzung train vs. teamLeader (Korrektur eines verbreiteten Missverständnisses).**
- **Fehlendes Knowledge-Pack** (neue Version) → `train --bootstrap`. Der **Normalfall** von `/upgrade`.
- **Echte neue Agenten-Rolle/Tool** nötig (z.B. ein „native-image-validator", den es noch nicht gibt) → `teamLeader` (CONCEPT §4, AGENTS.md §7). Die **Ausnahme**. `/upgrade` eskaliert hierhin nur, wenn eine Stufe eine Fähigkeit braucht, die kein bestehender Agent abdeckt — und stoppt diese Stufe als BLOCKED mit teamLeader-Vorschlag (kein autonomes Anlegen neuer Agenten über Nacht; Team-Erweiterung bleibt mensch-gegatet).

---

## 9. Phase F — Execute + Test-Loop + Retro

1. **`/flow` übernimmt** und arbeitet die Leiter-Items in `Depends-on`-Reihenfolge ab — unverändertes `coder → reviewer ⇄ Loop → tester → landen`-Spiel (CONCEPT §4b). Jede Stufe = ein `ng update`/Dependency-Bump + Schematics + Build/Tests grün als AC.
2. **Pro Stufe harte Gates:** kein Landen auf rotem Review/Test (bestehende Gates, unverändert). Der reviewer prüft zusätzlich den Dependency-Compat-Check (§13/Welle 6).
3. **Abschluss-Test:** nach der letzten Stufe voller Build + Test-Suite + Smoke; bei FAIL zurück in den Loop (Schleifenschutz max. 3 greift pro Item).
4. **Profil zurückschreiben:** erreichte Ziel-Versionen ins `profile` (`/flow` §5a-analoge Invalidierung von `adoption_validated_at` falls DB-Achse berührt).
5. **`retro` am Ende:** `/upgrade` triggert `/retro`, um die im Lauf gesammelten Lessons (`.claude/lessons/*`) in die Packs zu destillieren → das nächste Upgrade wird effizienter. Normaler PR+Gate-Weg (CONCEPT §5).

---

## 10. Hermetisches Pack-Loading (die `/reload-plugins`-Barriere auflösen)

**Problem (live erlebt).** Ein frisch gebootstrapptes Pack liegt erst im agent-flow-Source/PR. Damit `coder`/`reviewer`/`tester` es nutzen, müsste normalerweise gemergt + das Plugin ge-updatet + `/reload-plugins` ausgeführt werden — Letzteres kann ein autonomer Lauf nicht selbst auslösen. Das würde Voll-Autonomie brechen.

**Lösung: Knowledge-Staging-Dir + Loader-Override.**
1. `/upgrade` legt zu Lauf-Beginn ein **Staging-Verzeichnis** an (`.claude/upgrade/<run-id>/knowledge/`, gitignored) als Kopie der aktuell aktiven Packs (`${CLAUDE_PLUGIN_ROOT}/knowledge/`).
2. Es exportiert `AGENT_FLOW_KNOWLEDGE_DIR=<staging>` für den gesamten Lauf.
3. **Pack-Resolver-Override (Welle 4):** `coder`/`reviewer`/`tester`/`dba` lesen Packs **zuerst** aus `AGENT_FLOW_KNOWLEDGE_DIR`, Fallback `${CLAUDE_PLUGIN_ROOT}`. Reine Erweiterung des Resolvers, abwärtskompatibel (kein Override gesetzt → heutiges Verhalten).
4. `train --bootstrap` schreibt neue Packs **in den Staging-Dir** → sofort nutzbar, **ohne** Merge/Reload.

**Folge.** Der autonome Lauf ist **hermetisch** gegen den Plugin-Cache: Er kann beliebig viele Packs bootstrappen und sofort verwenden; die Durability (PRs gegen agent-flow) läuft asynchron und mensch-gegatet daneben. Nach dem Lauf kann der Staging-Dir verworfen werden (die Packs leben dann via gemergten PRs regulär weiter).

---

## 11. Voll-Autonomie: Failure-Isolation, Resume, Report

**Failure-Isolation.** Eine rote/blockierte Stufe darf den Lauf nicht hängen lassen:
- Stufe scheitert (Schleifenschutz erschöpft / unlösbarer Solver-Konflikt / Gap braucht teamLeader) → Item **Blocked**, im Report vermerkt.
- `/flow` arbeitet **unabhängige** Stufen weiter (der `Depends-on`-Graph isoliert: nur Nachfahren der blockierten Stufe werden übersprungen, parallele Achsen laufen weiter).

**Resume / Idempotenz.** Der Lauf-Zustand lebt **im Board + Profil**, nicht im Prozess-Speicher: abgeschlossene Stufen = `Done`, laufende = `In Progress`, der `upgrade`-Block im Profil hält `run-id` + erreichten Stand. Nach Absturz/Unterbrechung setzt ein erneutes `/upgrade` genau dort auf — der Solver ist deterministisch (§6), reproduziert also dasselbe Ziel-Set. **Resume-Pfad-Hinweis:** Der Override `AGENT_FLOW_KNOWLEDGE_DIR` (§10) lebt nur im Prozess; nach Neustart muss `/upgrade` (nicht ein nacktes `/flow`) den Lauf fortsetzen, damit der Staging-Dir wieder exportiert wird. Ein reines `/flow` degradiert sauber auf `${CLAUDE_PLUGIN_ROOT}` — Stufen, die ein **nur im Staging-Dir** existierendes (noch nicht gemergtes) Pack brauchen, scheitern dann am Gate, bis ihr Bootstrap-PR gemergt + das Plugin ge-reloadet ist; alle übrigen Stufen laufen.

**Harte Caps (unverändert + neu).** coder-Fix-Loop max. 3 Iterationen pro Item (CONCEPT §4); zusätzlich ein **Gesamt-Stufen-Timeout** (Profil-konfigurierbar) gegen Endlosläufe; nie Merge auf rotem Gate.

**Report + Notification.** Am Lauf-Ende erzeugt `/upgrade` einen **strukturierten Report** (was `Done`, was `Blocked` + Grund, welche agent-flow-Bootstrap-PRs offen sind, Ist→Ziel je Achse) und sendet eine **Push-Notification** (Overnight-Lauf → Mensch findet morgens das Ergebnis). Der Report wird als Kommentar an ein Tracking-Item gehängt.

**Sicherheits-Floor bleibt hart.** Autonomie senkt **nie** die Gates: reviewer-Drift-Gate, Security-Floor, Template-Diff-Gate (`/flow` §-Template-Gate), Test-Gate gelten unverändert.

---

## 12. Constraint-Schema (Pack-Header)

Detail-Schema + Backfill in `framework-build-subsystem.md` (Welle 2). Kurzform — additive, optionale Header-Felder in Framework-/Build-/Migration-Packs:

```yaml
requires:                       # harte Mindest-Anforderungen dieses Packs an andere Achsen
  java: ">=17"                  #   Sprach-Floor (SemVer-Range)
  build: { maven: ">=3.6.3", gradle: ">=8.14" }
compatible_with:                # weiche/bekannte Verträglichkeiten
  migration: { flyway: ">=10", liquibase: ">=4" }
incompatible:                   # harte Ausschlüsse (Solver-Konflikt)
  - container=undertow
```

**Quelle der Werte = die bereits in Sektion A belegte Prosa** (z.B. `spring-boot-4/A01` „Java 17 Baseline", `flyway-10/A01` „Java 17 Minimum"). Das Backfill macht die Fakten solver-fähig, ohne neue Wahrheiten zu erfinden. Pflege durch `train` (zusammen mit Sektion-A-Updates) — Constraints altern mit den Fakten mit.

---

## 13. Profil-Erweiterungen

```yaml
# NEU — Hilfsachse für Runtime-Ausschlüsse (z.B. Servlet 6.1 ⇒ kein Undertow)
container_runtime: tomcat | jetty | undertow | none   # optional, von /adopt aus Deps gesetzt

# NEU — Fortschritts-/Ziel-Block des laufenden Upgrades (transient bis Abschluss)
upgrade:
  run_id: <iso-datum-slug>           # Resume-Anker
  targets: { language: java@25, frameworks: ["spring-boot@4"], db_migration_tool: flyway@10 }
  status: planning | executing | done | blocked
  timeout_hours: 8                   # optional; Gesamt-Stufen-Timeout (null = kein Timeout)
```

Nach Abschluss werden die `targets` in die regulären Achsen-Felder übernommen und der `upgrade`-Block geleert (oder als Audit-Trail mit `status: done` belassen).

---

## 14. Abgrenzung & Risiken

- **Stretch von CONCEPT §9.** „Eingaben-freier Langlauf" dehnt die Autonomie-Haltung; bewusst gelöst durch „eine interaktive Session, kein Cron/API" (§1). Falls später echtes Cron gewünscht wird, ist das eine separate Entscheidung.
- **Solver-Lückenrisiko.** Solange Packs noch kein `requires:` führen, trägt der Web-Fallback die Last (langsamer, recherche-abhängig). Backfill (Welle 2) reduziert das; vollständige Abdeckung ist ein wachsender Bestand.
- **Bootstrap-Qualität autonom.** Ein über Nacht gebootstrapptes Pack ist nur so gut wie die Primärquellen-Recherche — es geht zwar als PR durchs Mensch-Gate, wird aber **im Lauf bereits verwendet**. Risiko-Minderung: reviewer-Gate pro Stufe fängt Pack-Fehler indirekt (roter Build/Review). Bekannte Restunschärfe wird im Report markiert.
- **Lange Läufe + Kontextgrenzen.** Sehr große Upgrades können eine Session-Kontextgrenze überschreiten → Resume (§11) ist die Absicherung; der Lauf ist so entworfen, dass er stückweise wieder aufsetzbar ist.

---

## 15. Implementierungs-Wellen

| Welle | Inhalt | Artefakte |
|---|---|---|
| **1** | Diese Spec | `docs/architecture/upgrade-subsystem.md` (+ CONCEPT/AGENTS-Verweise) |
| **2** | Constraint-Schema + Backfill | `framework-build-subsystem.md` (Schema §); `requires:`/`compatible_with:`/`incompatible:` in angular-21, spring-boot-3/4, flyway-9/10, java |
| **3** | `train --bootstrap` | `agents/train.md`, `skills/train/SKILL.md` |
| **4** | Loader-Override | `framework-build-subsystem.md` (Loader §); `agents/{coder,reviewer,tester,dba}.md` (AGENT_FLOW_KNOWLEDGE_DIR) |
| **5** | `/upgrade`-Skill + Solver | `skills/upgrade/SKILL.md`, `templates/_shared/upgrade-plan.md` |
| **6** | reviewer/tester + Profil-Achse | `agents/{reviewer,tester}.md` (Dependency-Compat-Check), `container_runtime`+`upgrade`-Block in `templates/*/profile.md` + `db-subsystem.md`, Verdrahtung in AGENTS.md/CONCEPT.md |

Jede Welle landet als eigener PR (reviewer-Check + Mensch-Approve, CONCEPT §5).
