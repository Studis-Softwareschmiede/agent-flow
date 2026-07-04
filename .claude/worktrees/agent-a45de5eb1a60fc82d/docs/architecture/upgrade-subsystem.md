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
2. **Pro Stufe harte Gates:** kein Landen auf rotem Review/Test (bestehende Gates, unverändert). Der reviewer prüft zusätzlich den Dependency-Compat-Check (§13/Welle 6). **Beachte die Execute-Disziplin-Feld-Lessons (§16):** Encoding-Pin pro java-Rung (§16-L1), OpenRewrite-Recipe-Bündelung (§16-L2), Lifecycle-Audit nach Test-Framework-Migration (§16-L3), Supervised-Runtime-Verify für ungetestete Pfade mit Breaking Changes (§16-L4), Online-Build nach Major (§16-L5).
3. **Abschluss-Test:** nach der letzten Stufe voller Build + Test-Suite + Smoke; bei FAIL zurück in den Loop (Schleifenschutz max. 3 greift pro Item). „Build + Unit grün" ist bei API-Breaking-Changes in **nicht unit-getesteten** Pfaden **kein** ausreichendes Gate → supervised Runtime-Verify (§16-L4).
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

---

## 16. Feld-Lessons (Execute-Disziplin)

> Aus realen `/upgrade`-Läufen via `retro` destillierte, **method-generalisierbare** Befunde (kein Pack-API-Wissen — das lebt in den Packs). Gilt für Phase F (§9). Quelle der initialen Einträge: climatedataanalyser-Lauf 2026-06-02 (java 11→21, spring-boot 2.6→3.3.13; SB4 BLOCKED).

- **§16-L1 — Language-Rung Encoding-Pin (java).** Bei jeder **java-version-Bump-Stufe** auf einer JDK-17-(oder älter-)Toolchain proaktiv `-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8` auf Surefire **und** Failsafe pinnen, **bevor** Tests laufen. Grund: JDK < 18 leitet `file.encoding` aus der Platform-Locale ab → Non-ASCII-Test-Daten (Umlaute in `@Sql`-Seeds u.ä.) werden auf Nicht-UTF-8-Locales falsch dekodiert; ein Bump kann grün auf der CI-JDK und rot auf der Ziel-JDK sein, ohne dass Produktivcode sich änderte. Detail + Reviewer-Schwere: `knowledge/java.md` `java/R16`. (Ab JDK 18 default UTF-8, JEP 400 — Pin nur für 17er-Stufen.)

- **§16-L2 — OpenRewrite Recipe-Ordering / Chicken-Egg.** Ein Framework-Major-Recipe migriert nicht automatisch alle Sub-Frameworks (gesehen: `UpgradeSpringBoot_3_x` migriert Spring Batch **nicht**). Ein nachgelagertes Sub-Recipe (z.B. `SpringBatch4To5Migration`) schlägt fehl, wenn der noch un-migrierte Code unter der neuen Major-Version **nicht kompiliert** — OpenRewrite kann dann keine Typ-Attribution durchführen (Henne-Ei). **Regel:** Framework-Major-Recipe + zugehörige Sub-Recipes in **derselben** `activeRecipes`-Liste (komma-separiert) gemeinsam aktivieren; ODER zuerst die kompilierbarkeits-brechenden Altreste manuell entfernen (Compile herstellen), **dann** das Sub-Recipe. Die Plan-Stufe (§7) sollte zusammengehörige Recipes als **eine** AC-Gruppe bündeln, nicht als getrennte, voneinander abhängige Stufen.

- **§16-L3 — Test-Framework-Migration kann tote Lifecycle-Methoden aktivieren.** Eine reine Annotation-Migration (gesehen: JUnit 4 `@Before` → JUnit 5 `@BeforeEach` via OpenRewrite) kann eine Lifecycle-Methode **erstmals zur Ausführung bringen**, die unter dem alten Framework still ignoriert wurde (eine `@Before`-annotierte Methode in einer Klasse, deren Runner sie nie aufrief) → Testdaten/Verhalten ändern sich, obwohl „nur Annotationen migriert" wurden. **Regel:** Nach Test-Framework-Migration die **neu laufenden** `@BeforeEach`/`@AfterEach`/`@BeforeAll`-Methoden auditieren (Diff der tatsächlich ausgeführten Setups), nicht nur den grünen Build vertrauen. Reviewer-Hook: `agents/reviewer.md` §4a(d).

- **§16-L4 — „Compile + Unit grün" ≠ verifiziert; ungetestete Runtime-Pfade brauchen Supervised-Verify.** Code-Pfade ohne Unit-Coverage (gesehen: Spring-Batch-Item-Reader / File-Import, von der Test-Suite nicht abgedeckt) können nach einem Major-Bump mit Breaking API-Änderungen **kompilieren und alle Tests bestehen, aber zur Laufzeit brechen** (z.B. entfernte no-arg-Konstruktoren, verschobene Packages, `saveOrUpdate`→`merge`). **Regel:** Erkennt eine Upgrade-Stufe einen API-Breaking-Change in einem **nicht unit-getesteten** Pfad, ist „Build+Unit grün" **kein** ausreichendes Stufen-Gate → Stufe als **supervised Runtime-Verify** markieren (Mensch verifiziert den Pfad real, z.B. echten File-Import fahren) **vor** Merge, statt autonom zu landen. Andernfalls Stufe BLOCKED (§11) mit Begründung. Verhindert false-green Merges bei SB4/Batch6/Hibernate7-Sprüngen. (Normative Ausgestaltung dieses Prinzips für DB-/Treiber-/Image-berührende Rungs: §17.)

- **§16-L5 — Stepping-Stones + Online-Build nach Major.** Mehrere Majors einer Achse **stufenweise** über aufeinanderfolgende Recipes fahren (z.B. spring-boot 3.3→3.5→4.0), **nach jedem Major grün verifizieren**, bevor der nächste läuft — bestätigt das Leiter-Prinzip (§1, „eine Major-Stufe nach der anderen"). Praxis-Detail: `mvn -o` (offline) **bricht direkt nach einem Major-Bump**, weil die neuen Plugin-/Dependency-Versionen noch nicht im lokalen Cache liegen → die erste Build-Verifikation einer neuen Major-Stufe **online** fahren.
## 17. Runtime-Verify-Pflicht für laufzeit-berührende Rungs (Unit-Gate-Blindfleck)

> Universeller Kern, repo-agnostisch. Provenance: `retro` aus einem `/upgrade`-Folge-Debug (climatedataanalyser, SB-3.3-Preview bootete nicht). Das **Meta-Muster** ist hier normativ; die belegende Instanz (Flyway-Modul/Dialekt/Container-Schreibpfad) lebt als Tool-Fakt/Template-Prinzip (`migration/flyway-10.md §B`, `templates/java/Dockerfile`, `templates/_shared/db-mysql/`).

**Kern-Befund.** **Grüne Unit-Tests ≠ funktionierendes Upgrade**, sobald ein Rung Laufzeit-Oberflächen berührt, die Unit-Tests **strukturell** nicht abdecken:
- die **echte DB** (Engine **+** JDBC-Treiber **+** Migrationstool — eine Major-Bump des BOM kann jedes der drei einzeln brechen),
- das **gepackte Image** (Runtime-User, Dateisystem-Rechte, gepinnte Base-Images — nicht der Test-Classpath),
- **nicht-unit-getestete IO-/Batch-Pfade** (FTP/Datei-Schreibziele, Stream-Reader), die der H2/Mock-Layer per Konstruktion umgeht.

Ein Major-Upgrade kann hier mit **vollständig grünem Unit-Gate** ein **kaputtes Produktiv-Image** mergen — die Abnahme muss genau diese Flächen prüfen, sonst ist „done" eine Lüge.

**Normative Folgen.**

- `§17-R1` (**Runtime-Verify als AC des Rungs selbst, nicht nachgelagert**). Ein Rung, dessen Diff DB-Engine, JDBC-Treiber, Migrationstool-Version (auch nur BOM-transitiv) oder das Runtime-Image berührt, ist **erst dann `done`**, wenn ein **Real-Engine-Runtime-Smoke** (echte DB-Instanz, gepacktes Image bootet + Migrationen laufen + ein nicht-unit-getesteter IO-Pfad einmal durchläuft) grün ist. Dieser Verify ist **Akzeptanzkriterium des Major-Rungs selbst** und als harte `Depends-on`-Vorbedingung modelliert — **kein** separater nachgelagerter Rung, der „später" käme (sonst landet der defekte Rung schon).

- `§17-R2` (**Reviewer-Trigger — DB/Treiber/Image-berührender Diff**). Berührt der Stufen-Diff `pom`/`build`-DB-Deps (JDBC-Treiber, Migrationstool-Module), Datasource-Properties, eine **BOM-Version, die das Migrationstool transitiv hebt**, oder das `Dockerfile`/Runtime-Image → **Real-DB-Runtime-Smoke Pflicht vor „done"**. Fehlt er, ist das ein **Critical**-Befund (`upgrade/§17-R2`) — grüne Unit-Tests genügen für diese Diff-Klasse nicht.

- `§17-R3` (**DB-/Tool-/Base-Images pinnen, keine floating Major-Tags**). DB- und Migrations-Images sowie Runtime-Base-Images werden auf eine **stabile Version** gepinnt (kein floating `:8`/`:latest`-Major, der unter dem Lauf von 8.0 auf 8.4 driftet und die Tool-Engine-Erkennung bricht). Ein floating Major-Tag in einem upgrade-berührten Image ist ein **Important**-Befund.

Diese Regeln ergänzen die Gates aus §9/§11; sie senken **nie** ein bestehendes Gate, sondern schließen den Unit-Gate-Blindfleck für die laufzeit-berührende Diff-Klasse.
