# Architecture — Framework-/Build-Subsystem (pluggable, multi-axis)

> **Bindend.** Diese Spec beschreibt **wie** das `agent-flow`-Plugin Frameworks (Spring, React, Django …) und Build-Tools (Maven, Gradle, npm, uv, cargo …) als erstklassige, pluggable Achsen behandelt — additiv zur Sprach-Achse (`lang`) und zur DB-Achse (`db_dialect`). Implementierung erfolgt in sechs Wellen (Spec → Schema/Loader/Train-CLI → Tester-Dispatch → Adopt/new-project-Detection → Pilot-Packs → Retro-Schutzgitter; §12). Abweichungen sind Review-Kriterium.

---

## 1. Zweck & Scope

**Zweck.** Bisher kennt das Plugin nur die Sprach-Achse (`knowledge/<lang>.md`) und die DB-Achse (`db_dialect` + `knowledge/sql*.md` | `mongodb.md`). Reale Projekte unterscheiden sich aber zusätzlich nach Framework (Java ≠ Spring; Java ≠ Quarkus) und Build-Tool (Java ≠ Maven; Node ≠ npm). Diese Spec macht beide Aspekte zur **erstklassigen, pluggable** Achse: explizite Felder im Profil steuern Knowledge-Pack-Auswahl, Tester-Smoke-Befehl und Adopt-Detection.

**Motivation (begründet).**

- **Sprache ≠ Framework.** Java-Wissen ohne Spring-Boot-Wissen ist für ein Spring-Boot-Projekt unvollständig (Auto-Configuration, Starter-BOMs, Actuator). Umgekehrt ist Spring-Boot-Wissen ohne Java-Floor halbverdaut. Beide Layers müssen unabhängig pflegbar sein.
- **Build-Tool ≠ Sprache.** `mvn verify` vs. `./gradlew build` vs. `npm test` ist eine eigene Wissens- und Disziplin-Achse (Profile/Phases bei Maven; Configurations bei Gradle; Workspaces bei npm/pnpm). Ein Java-Pack, der Maven-Befehle annimmt, brennt jedes Gradle-Projekt.
- **Trennung erlaubt Cross-Compat.** Spring-Boot läuft auf Java **oder** Kotlin → Framework-Pack muss sprach-agnostisch dort sein, wo es sprach-agnostisch ist.

**Out of Scope (P1).**

- **Keine Cross-Sprach-Frameworks.** Spring-Boot ist Java/Kotlin — kein Pack-Sharing für hypothetische .NET-Spring-Ports. Cross-Sprach-Stacks (z.B. .NET) kommen als eigener späterer Wellen-Schub.
- **Kein automatisches Pack-Wechseln bei Framework-Upgrade.** Wechsel von `spring-boot@2` auf `spring-boot@3` ist ein bewusster User-Edit im Profil (§5). Plugin folgt, fragt nicht zurück, schlägt aber bei fehlendem Pack laut auf (`§5 Loader-Verhalten`).
- **Kein eigener Agent pro Framework.** `coder` bleibt generisch; Framework-Wissen kommt via Pack-Selektion, nicht via Agent-Multiplikation.

---

## 2. Profil-Erweiterung (3-Achsen)

Neue Felder im `.claude/profile.md`. Die Sprach-Achse (`lang`) bleibt unverändert; **zwei neue Felder** kommen hinzu:

```yaml
lang: "java" | "ts" | "py" | "rust" | ...        # bestehend; Single-Value ODER (neu) Array für Mono-Repos
                                                  #   Single:  lang: "java"
                                                  #   Multi:   lang: [java, ts]       (z.B. Spring-Boot-Backend + Angular-Frontend in einem Repo)
build: "maven" | "gradle" | "npm" | "pnpm" | "uv" | "cargo" | "none"   # NEU, Pflicht ab Sprachen mit Build-Tool; "none" für Bash-Skripte/statische Seiten
frameworks: []                                    # NEU, Array, optional; Form: ["spring-boot@3", "spring-data@3"]
```

**Pflicht-/Optional-Matrix:**

| Feld | Status | Default beim Scaffold |
|---|---|---|
| `lang` | Pflicht (bestehend); Scalar ODER Array (Multi-Lang-Mono-Repos, siehe unten) | aus Sprach-Auswahl `/new-project` / `/adopt` |
| `build` | Pflicht ab Sprachen mit Build-Tool | aus Detection (§6); explizit `none` für Bash/statisch |
| `frameworks` | Optional (Array, Default `[]`) | aus Detection (§6); leer ⇒ kein Framework-Pack |

**Form des `frameworks`-Eintrags.** `"<id>@<major>"` (z.B. `"spring-boot@3"`). Major ist Pflicht ab Frameworks, die einen Cut hatten — Loader matcht über `framework_version_range`-Header (§3). Details und Faustregel: [`knowledge/_meta/versioning.md`](../../knowledge/_meta/versioning.md).

**Multi-Lang-Form (Mono-Repos).** Ist `lang` als Array gesetzt (z.B. `[java, ts]`), gilt jede gelistete Sprache als „primäre Sprache" des Repos. Der Pack-Loader lädt **alle** Sprach-Packs parallel (§3); der Reviewer wendet **Per-File-Dispatch** an — die Datei-Endung entscheidet, welcher Sprach-Pack für eine konkrete Datei greift (`*.java` → `java.md`, `*.ts`/`*.tsx` → `ts.md`, etc.). Floor-Packs (z.B. `security.md`) gelten dateiunabhängig. Scalar-Form (`lang: "java"`) ist YAML-äquivalent zu `lang: [java]` und bleibt der **Default** für Single-Sprache-Repos — die Multi-Form ist explizit für Mono-Repos mit mehreren primären Sprachen (über Maven Multi-Modul, npm/pnpm-Workspaces, Cargo-Workspaces oder vergleichbare Strukturen).

**Abgrenzung zu `db_dialect` (siehe `docs/architecture/db-subsystem.md` §2):** `db_dialect` ist und bleibt **single-value** (eine App = eine DB). `lang`-Multi ist eine andere Klasse: ein Mono-Repo ist mehrere logisch getrennte Apps in einem Repo, mit eigenen Source-Trees pro Sprache — die `lang`-Achse muss das abbilden. Die DB-Achse spannt das nicht (auch ein Java+Angular-Repo nutzt typischerweise EINE DB).

**Backwards-Compat.** Fehlende `build`-Zeile in bestehenden Profilen → Loader interpretiert als „kein Build-Pack laden" (analog zum DB-Subsystem-Fallback). Beim nächsten `/adopt` setzt die Heuristik (§6) das Feld; alternativ wird interaktiv nachgefragt. Fehlende `frameworks`-Zeile → behandelt wie `frameworks: []` (kein Framework-Pack).

---

## 3. Knowledge-Pack-Struktur

**Neu (Welle 2/5):**

```
knowledge/
  java.md                       # Sprach-Floor (bestand)
  ts.md                         # Sprach-Floor (bestand: js.md → analog)
  ...
  frameworks/
    spring-boot-3.md            # Major-Range-Pack
    spring-data-3.md
    quarkus-3.md
    react-18.md
    react-19.md
    django-5.md
  build/
    maven.md
    gradle.md
    npm.md
    pnpm.md
    uv.md
    cargo.md
  _meta/
    versioning.md               # Faustregel-Doku (Cut vs. Tag)
```

**Pack-Auswahl-Regel** (gilt für `coder`, `reviewer`, `tester`, `train`, `retro`):

```
ALWAYS  für JEDE Sprache in profile.lang (Scalar → 1-Element-Array normalisiert): knowledge/<lang>.md
IF profile.frameworks    → für jedes f in frameworks: knowledge/frameworks/<f>.md
IF profile.build != none → knowledge/build/<profile.build>.md
```

**Per-File-Dispatch bei Multi-Lang** (Reviewer-/Tester-spezifisch): wenn `profile.lang` mehr als eine Sprache enthält, wendet der Reviewer für jeden geänderten File **den passenden Sprach-Pack** an — Auswahl per Datei-Endung gemäß einer expliziten Mapping-Tabelle, die im Reviewer-Agent verankert ist (siehe `agents/reviewer.md` Schritt 5). Die Coder-Guidance aller geladenen Sprach-Packs liest der Coder vollständig (er weiß noch nicht, welche Files er gleich editieren wird); der Per-File-Dispatch betrifft nur die Reviewer-Checklist-Anwendung. Floor-Packs (`security.md`) gelten dateiunabhängig — Floor wird IMMER auf alle Dateien angewendet.

**Pack-Header (Pflicht-Frontmatter ab framework-/build-Packs):**

```yaml
---
pack: frameworks/spring-boot-3
pack_version: 1.0                              # SemVer, intern; bumpe bei jedem Edit (train/retro)
framework_version_range: ">=3.4, <4.0"         # nur framework-Packs; build-Packs lassen frei oder leer
pack_date: 2026-05-31                          # last_trained-Äquivalent
primary_sources:
  - https://docs.spring.io/spring-boot/reference/
  - https://github.com/spring-projects/spring-boot/releases
non_sources: [baeldung.com, dev.to, medium.com]
---
```

**Header-Pflicht für build-Packs:** identisch, außer `framework_version_range` (entfällt oder leer). `primary_sources` zeigt auf das offizielle Build-Tool-Doc (z.B. `maven.apache.org`).

**Hinweis zu `pack_version`:** Pflicht-Format ist `<major>.<minor>` (zwei-stellig) — patch-Level nicht nötig, weil Pack-Patches als ganz neuer commit/PR landen und das `pack_date` der Wahrheits-Marker ist.

**Header-Pflicht für Sprach-Packs (bestand):** wird in dieser Spec **nicht** geändert — Sprach-Packs behalten ihren bisherigen Aufbau, damit Bestandsprojekte stabil bleiben.

**Regel-IDs pro Pack-Namespace** (analog DB-Subsystem §3): `spring-boot/R<NN>`, `react/R<NN>`, `maven/R<NN>`, `gradle/R<NN>`. Begründung: stabile IDs für das Observability-Ledger (CONCEPT §5a).

**Pack-Constraints (optionale Solver-Metadaten — `docs/architecture/upgrade-subsystem.md` §12).** Framework-/Build-/Migration-Packs dürfen zusätzlich maschinenlesbare Achsen-Constraints im Frontmatter führen, die der `/upgrade`-Kompatibilitäts-Solver konsumiert:

```yaml
requires:                       # harte Mindest-Anforderungen an andere Achsen (SemVer-Range)
  java: ">=17"
  node: "^20.19.0 || ^22.12.0 || ^24.0.0"
  typescript: ">=5.9 <6.0"
  build: { maven: ">=3.6.3", gradle: ">=8.14" }
compatible_with:                # bekannte Verträglichkeiten (weich, informativ für den Solver)
  migration: { flyway: ">=10", liquibase: ">=4" }
incompatible:                   # harte Ausschlüsse (erzeugen einen Solver-Konflikt)
  - container=undertow
```

- **Optional + abwärtskompatibel:** fehlen die Felder, ändert sich nichts — Loader/Reviewer/Tester ignorieren sie; **nur** der `/upgrade`-Solver liest sie. Bestandspacks ohne Constraints bleiben gültig.
- **Quelle = Sektion-A-Fakten:** die Werte spiegeln bereits belegte „Stable API & Deprecations"-Regeln maschinenlesbar wider (z.B. `spring-boot-4/A01` „Java 17 Baseline" → `requires.java: ">=17"`). **Keine neuen Wahrheiten** — jede Constraint hat ihre Quelle in Sektion A desselben Packs.
- **Pflege durch `train`** zusammen mit Sektion A: ändert sich ein Floor in den Release-Notes, aktualisiert `train` Regel **und** Constraint im selben PR. Constraints altern so mit den Fakten mit.
- **Schlüssel-Konvention:** Achsen-Namen folgen den Profil-Achsen — `java`/`node`/`typescript` (Sprach-/Runtime-Floors), `build.<tool>`, `migration.<tool>`, `frameworks.<id>`; `incompatible` listet `<achse>=<wert>`-Ausschlüsse (z.B. `container=undertow`).

---

## 4. Pack-Sektionen (Drei-Schichten-Aufbau)

Jeder framework-/build-Pack hat die folgenden Sektionen mit klarer Schreib-Hoheit:

- `## A. Stable API & Deprecations` — von `train` befüllt (externe Wahrheit, Quellen-getrieben). Hier landen API-Lifecycle-Aussagen, Deprecation-Versionen, Breaking-Changes aus Release-Notes.
- `## B. Anti-Patterns aus Einsatz` — von `retro` befüllt (Felderfahrung, Projekt-getrieben). Hier landen Patterns, die in der Praxis brennen — mit Provenance (Projekt + Datei/PR; §9-G2).
- `## C. Konventionen (Floor)` — manuell gepflegt. Sowohl `train` als auch `retro` fassen das **nur mit User-Approval** an (PR-Body markiert solche Änderungen explizit).
- `## Coder-Guidance` / `## Reviewer-Checklist` / `## Test-Approach` — Standard-Sektionen wie in Sprach-Packs, ergänzend. Beide Agenten dürfen hier ergänzen (train für API-Updates; retro für Felderfahrung), sofern die Aussage zu ihrer Schreib-Hoheit passt.

**Konflikt-Frei.** `train` schreibt **nie** in B. `retro` schreibt **nie** in A. Beide schreiben PRs (kein Direct-Push). Reviewer prüft die Schreib-Hoheit als Hard-Check: ein PR von `train`, der Sektion B berührt, ist `CHANGES-REQUIRED`; analog für `retro` in Sektion A.

**Sektions-Reihenfolge im Pack-File** (kanonisch, damit Reviewer Diffs leicht zuordnet): A → B → C → Coder-Guidance → Reviewer-Checklist → Test-Approach.

**Verbatim-Wording-Disziplin (Pack-Authoring-Regel, Lehre aus PR-I — sb-2/A02+A04 mussten entschärft werden).** Bei Aussagen mit **harten Versions- oder Datumsangaben** (z.B. „since 2.5.6", „OSS-EOL 2023-11-18") MUSS der Pack-Autor entweder:

1. Ein **wörtliches Zitat + Anchor-Link** aus der Primärquelle im Pack-Regel-Body haben (`[src: URL#anchor — verbatim: „<exaktes Zitat>"]`), ODER
2. Die Aussage **entschärfen** mit `verify`-Marker (z.B. „Java 17 wird in späteren 2.x-Releases unterstützt — *verify gegen die Release-Note der eingesetzten 2.x-Version*"), ODER
3. Auf das konkrete Datum/die konkrete Version **verzichten** und stattdessen auf die Primärquelle verweisen („siehe `spring.io/projects/spring-boot/#support` für aktuelle Daten").

Diese Regel ist die symmetrische Verlängerung von `reviewer/R01` und `coder/R02` (Verbatim-Pflicht bei Klassifikations-Widerlegungen) ins Pack-Material. Pack-Autor = `train`-Agent ODER manueller Pack-Anleger. Der Reviewer prüft das beim Pack-Review als Hard-Check: harte Datums-Behauptung ohne Verbatim/Anchor/verify-Marker → **Important** mit Verweis auf diese Regel.

---

## 5. Versions-Strategie

**Hybrid.** Frameworks werden versioniert nach **Cut/Tag-Faustregel** (Detail-Doku: [`knowledge/_meta/versioning.md`](../../knowledge/_meta/versioning.md)):

- **Major-Cut → eigener Pack** wenn Migration Code-Patterns **kaputt macht oder verbietet** (Spring-Boot 2→3 mit Jakarta-Namespace; React 17→18 mit Concurrent-Render-Semantik).
- **Minor-Tag → gleicher Pack** wenn alter Code weiterläuft (Spring-Boot 3.3→3.4: neue Regel mit `[since: 3.4]`-Marker im Body; Java 17→21 als additive Sprach-Features).

**Profile-Form.** `framework@major` (z.B. `spring-boot@3`). Loader matcht den Major aus dem Profil gegen den `framework_version_range`-Header der Pack-Datei (§3).

**Loader-Verhalten bei No-Match.** Profil sagt `spring-boot@3`, aber kein Pack mit `framework_version_range` umfasst `3.x` → Loader bricht mit klarer Fehlermeldung ab (`Pack "frameworks/spring-boot-3" fehlt; lege ihn an oder korrigiere das Profil.`). **Kein Silent-Fallback** auf einen anderen Major.

**Pack-Anlage-Pflicht bei Cut.** Ein neuer Pack wird durch Kopie + Anpassung des alten erzeugt. Der alte Pack wird **NICHT gelöscht** (Bestandsprojekte verlassen sich darauf), bekommt aber im Header einen Endlebenszyklus-Marker: `eol: <datum>` oder `superseded_by: <neuer-pack-id>`. Detail-Begründung und Beispiel-Tabelle: [`knowledge/_meta/versioning.md`](../../knowledge/_meta/versioning.md).

**Range-Matching-Semantik (Loader-Verhalten):** Der Pack-Loader matcht `frameworks: ["<id>@<major>"]` aus dem Profil gegen den `framework_version_range`-Header der Pack-Datei. Match-Regel: der Major aus dem Profil muss in das Range-Intervall fallen. Beispiel: Pack-Range `">=3.0, <4.0"` matcht `spring-boot@3`. Mehrere Packs mit überlappenden Ranges für denselben `<id>` sind nicht erlaubt (Build-Time-Fehler im Pack-Loader).

**Pack-Pfad-Auflösung (Loader-Override, `AGENT_FLOW_KNOWLEDGE_DIR`).** Alle Pack-Pfade, die die Agenten (`coder`/`reviewer`/`tester`/`dba`) als `${CLAUDE_PLUGIN_ROOT}/knowledge/...` lesen, werden über **eine** Präzedenz aufgelöst:

1. ist die Umgebungsvariable **`AGENT_FLOW_KNOWLEDGE_DIR`** gesetzt UND existiert dort die gesuchte Pack-Datei → **diese** lesen;
2. sonst Fallback auf `${CLAUDE_PLUGIN_ROOT}/knowledge/...` (heutiges Verhalten).

**Zweck:** hermetisches Pack-Loading für autonome `/upgrade`-Läufe (`docs/architecture/upgrade-subsystem.md` §10) — frisch via `train --bootstrap` erzeugte Packs liegen im Staging-Dir und werden **sofort** genutzt, ohne Merge/`/reload-plugins`. **Abwärtskompatibel:** ist `AGENT_FLOW_KNOWLEDGE_DIR` nicht gesetzt (Normalfall), gilt unverändert der Plugin-Cache. Die Override-Auflösung ist **pro Datei** (ein Pack nur im Cache, ein anderes nur im Staging-Dir → beide werden gefunden). `${CLAUDE_PLUGIN_ROOT}` bleibt für **Schreib**-Operationen (PRs via Source-Klon) wie gehabt read-only; der Override betrifft nur das **Lesen** der Packs.

**Major-Optionalität:** Frameworks, die noch nie einen Cut hatten (z.B. `fastapi`, `flask` Stand 2026), dürfen ohne `@<major>` im Profil stehen (`frameworks: ["fastapi"]`). Der Loader nimmt dann den einzigen vorhandenen Pack-File-Match. Sobald ein Cut entsteht (z.B. `fastapi-2.md` neu), wird `@<major>` im Profil Pflicht — sonst Build-Time-Fehler („mehrdeutiger Match: fastapi-1.md ODER fastapi-2.md").

---

## 6. Adopt-Heuristik (Framework/Build-Detection)

Analog zur DB-Detection in `db-subsystem.md` §2: kanonische Signal-Palette mit Confidence-Stufen. **`skills/adopt/SKILL.md` spiegelt diese Tabelle 1:1** — neue Signale (z.B. künftige Build-Tools wie `bun`, `deno`, `bazel`) werden **zuerst hier** ergänzt, dann in der Skill nachgezogen (gleicher PR, kein Drift).

| Signal | → setzt | Confidence |
|---|---|---|
| `pom.xml` im Repo-Root | `build: maven` | high |
| `build.gradle` / `build.gradle.kts` / `settings.gradle{,.kts}` im Root | `build: gradle` | high |
| `package.json` + `package-lock.json` | `build: npm` | high |
| `pnpm-lock.yaml` | `build: pnpm` | high |
| `pyproject.toml` + `uv.lock` | `build: uv` | high |
| `Cargo.toml` | `build: cargo` | high |
| `pom.xml` enthält `spring-boot-starter-parent` oder dep `org.springframework.boot:*` | `frameworks += spring-boot@<major>` | high |
| `build.gradle*` enthält `org.springframework.boot` (plugin oder dep) | `frameworks += spring-boot@<major>` | high |
| `pom.xml`/`build.gradle*` enthält `io.quarkus` | `frameworks += quarkus@<major>` | high |
| `package.json` dep `react` (Version → Major) | `frameworks += react@<major>` | high |
| `package.json` dep `vue` | `frameworks += vue@<major>` | high |
| `package.json` dep `@angular/core` | `frameworks += angular@<major>` | high |
| `requirements.txt`/`pyproject.toml` mit `django>=` | `frameworks += django@<major>` | high |
| `requirements.txt`/`pyproject.toml` mit `fastapi>=` | `frameworks += fastapi@<major>` | high |
| `requirements.txt`/`pyproject.toml` mit `flask>=` | `frameworks += flask@<major>` | high |
| sonst (Sprach-Build-Tool unklar) | **Frage stellen** (`AskUserQuestion` mit den Enum-Werten + `none`) | — |

**Major-Extraktion.** Aus der Dep-Version den ersten Major nehmen — `react@^18.2.0` → `react@18`; `react@~19.0.0` → `react@19`; `angular@~13.3.2` → `angular@13` (Tilde mit 3-Stellen-Patch, analog Caret); `react@>=17 <19` → `react@17` (erster Major im Range) + **Warnung** im Adopt-Output („Dep spannt Majors 17–18; gepinnt auf 17; korrigiere Profil bei Bedarf"). Spec-Ranges mit Wildcards (`*`, `x`) ohne Untergrenze → Frage an User.

**Python-Signal-Fallback:** Liefert `requirements.txt` oder `pyproject.toml` einen Framework-Namen OHNE Version-Pin (`django` statt `django>=5.1`), wird Major-Extraktion via `pip index versions <name>` oder Pack-Default versucht. Schlägt das fehl → AskUserQuestion mit „kein Major bestimmt — bitte angeben".

**Confidence-Semantik.** `high` heißt: Signal ist eindeutig — Detection wird vorgeschlagen, User-Bestätigung erfolgt **trotzdem** (analog DB-Subsystem §9: immer Rückfrage, auch bei `high`). Confidence-Stufen sind Hinweis für Audit-Trail/Logs.

**Scan-Tiefe (Spec-Amendment 2026-05-31, Dogfood-Lehre aus climatedataanalyser).** `/adopt` scannt **nicht** generisch rekursiv — sonst würden `node_modules/`, `target/`, `vendor/`, `dist/` etc. false-positives erzeugen. Stattdessen **explizite Marker-getriebene** Sub-Modul-Erkennung:

| Marker | Welche Sub-Modul-Pfade werden zusätzlich gescannt |
|---|---|
| Maven Multi-Modul: `<packaging>pom</packaging>` + `<modules>` im Root-pom | alle in `<modules>` gelisteten Pfade |
| npm/pnpm Workspaces: `workspaces` (Array oder Glob) in Root-`package.json` | alle expandierten Workspace-Pfade |
| Cargo Workspace: `[workspace].members` in Root-`Cargo.toml` | alle gelisteten Member-Pfade |
| pnpm `pnpm-workspace.yaml` | alle expandierten Pfade |
| (kein Marker) | nur Repo-Root scannen |

**Repos ohne expliziten Marker**, die Sub-Trees mit eigenen Build-Files haben → `/adopt --root <subdir>` separat aufrufen (Skill-Flag). Default-Adopt-Lauf bleibt strikt root + Marker-Pfade.

**Konsequenz fürs Profil:** Multi-Lang-Detection (§2 Multi-Lang-Form) und Polyglott-Trigger (§7) greifen nur, wenn die Sub-Modul-Marker das jeweilige Sub-Modul sichtbar machen. Ohne Marker bleibt das Sub-Tree unsichtbar — bewusst, weil generisches Scanning zu viele false-positives erzeugt.

---

## 7. Polyglott-Trigger (Framework-Variante)

**Mechanismus-Wiederverwendung.** Identisch zum Polyglott-Trigger im DB-Subsystem (siehe `db-subsystem.md` §16-R1 + `skills/adopt/SKILL.md` Schritt 2a.1): wenn `/adopt` 2+ **HIGH-Confidence** Frameworks für **dieselbe Sprache** entdeckt (z.B. Spring-Boot + Quarkus im selben Java-Modul, oder Vue + Angular im selben TS-Modul), wird der Polyglott-Pfad ausgelöst:

1. **User-Choice** via `AskUserQuestion` — welcher Framework wird P1 (= primärer Pack); der andere kommt ins Backlog.
2. **Auto-Backlog-Issue** mit Label `polyglott-needed` + `architecture`, Titel `⚠ POLYGLOTT-BEDARF: <X> + <Y> in <lang> — P2-Architektur-Erweiterung nötig`, Body mit Evidence + §7-Verweis.
3. **Console-Output** klar abgesetzt (`============ ⚠ Polyglott detected ============`).

**Was zählt NICHT als Framework-Polyglott:**

- **Companions** (Redis, Memcached, Search-Engines) zählen nicht — sie sind nicht Framework, sondern Sidecars (siehe `db-subsystem.md` §17).
- **Polyglott über verschiedene Sprachen** ist normal (Java-Backend + React-Frontend im Mono-Repo) und triggert **NICHT**. Die Heuristik gruppiert die Detection nach `profile.lang` — der Trigger feuert nur, wenn die Konfliktmenge innerhalb **einer** Sprach-Bucket liegt.
- **Spring-Boot + Spring-Data + Spring-Security** im selben Modul ist **kein** Polyglott — das sind komplementäre Module derselben Framework-Familie. Die Heuristik unterscheidet „Familie" (gleicher Prefix wie `spring-*`) von „rivalisierende Frameworks" (Spring-Boot vs. Quarkus).

**Mehrere Frameworks im Profil sind legitim** (`frameworks: ["spring-boot@3", "spring-data@3"]`) — Polyglott meint nur **rivalisierende** Frameworks.

---

## 8. Train-Erweiterung

**`/train <pack-id>` Resolver** (Welle 2):

- **Sprach-Pack:** `lang` aus `knowledge/<id>.md` (Bestand).
- **Framework-Pack:** `frameworks/<id>.md` aus `knowledge/frameworks/<id>.md` — mit oder ohne `-<major>`-Suffix. Resolver versucht zuerst exakt (`spring-boot-3` → `knowledge/frameworks/spring-boot-3.md`), dann mit `@<major>` aus dem Profil (`spring-boot` → `knowledge/frameworks/spring-boot-<profile.major>.md`).
- **Build-Pack:** `build/<id>.md` aus `knowledge/build/<id>.md` (z.B. `maven` → `knowledge/build/maven.md`).
- **Ambiguität (id in 2+ Ordnern):** Fehlermeldung mit Optionsliste — **kein Default-Wahl** („id `react` mehrdeutig: knowledge/frameworks/react-18.md, knowledge/frameworks/react-19.md — präzisiere via `/train frameworks/react-18`").

**Quellen-Disziplin.** `train` respektiert den Pack-Header (§3):

- `primary_sources` — Pflicht-Quellen. Mindestens eine muss im PR-Body als Beleg pro neu/geänderter Regel zitiert sein (verbatim-Pflicht analog `reviewer/R01`, LEARNINGS).
- `non_sources` — verbotene Quellen. `train` darf von dort weder zitieren noch ableiten; Reviewer rejected entsprechende PRs als `CHANGES-REQUIRED`.

**Schreib-Hoheit.** `train` schreibt **nur** in Sektion A (Stable API & Deprecations) und ergänzt optional `Coder-Guidance` / `Reviewer-Checklist` / `Test-Approach`. Sektion B (Anti-Patterns aus Einsatz) bleibt `retro`-Hoheit — Berührung durch `train` → reviewer `CHANGES-REQUIRED` (§4 Konflikt-Frei-Regel).

**`pack_version`-Bump.** Jeder train-PR, der einen Pack ändert, bumpt `pack_version` im Header um Minor (oder Major bei Cut). `pack_date` wird auf den Tag des Trains gesetzt.

---

## 9. Retro-Erweiterung — 4 Schutzgitter

Promotionen aus Projekt-Lessons in Framework-/Build-Packs sind **gefährlich** (kleine Stichprobe, schnell falsch generalisiert). Diese vier Schutzgitter sind kanonisch und bindend:

1. **Frequenz-Schwelle.** Ein Pattern muss in **≥2 verschiedenen Projekten** UND **≥2 verschiedenen Code-Stellen** vorkommen, bevor `retro` es in einen Pack promoten darf.

   **Single-Projekt-Kandidaten → `Proposed`-Wartezimmer (HART, Amendment 2026-06-10).** Eine Single-Projekt-Lesson, die generalisierbar erscheint (= wäre bei Zweit-Beleg ein Pack-/Agent-Def-Kandidat), wird NICHT nur projekt-lokal gelassen, sondern zusätzlich als **`Proposed`-Zeile in `LEARNINGS.md`** geparkt. Begründung: `retro` liest pro Lauf nur (a) `<dieses-repo>/.claude/lessons/*` + (b) das geteilte `LEARNINGS.md`. Die projekt-lokalen Lessons sind also **nicht** cross-repo-sichtbar — `LEARNINGS.md` ist die **einzige** Brücke, über die ein späterer Lauf in einem *anderen* Repo die erste Evidenz wiederfindet. Ohne die `Proposed`-Zeile kann G1 (≥2 Projekte) faktisch **nie** erreicht werden, egal wie oft sich das Pattern wiederholt. (Triviale/rein projektspezifische Lessons ohne Generalisierungs-Aussicht bleiben rein lokal — kein `LEARNINGS.md`-Spam.)

   **Verfall der `Proposed`-Einträge (HART, Amendment 2026-06-10).** Damit das Register nicht monoton mit Eintagsfliegen wächst, trägt jede `Proposed`-Zeile ein **`expires`-Datum = Eintrags-/letztes-Sichtungs-Datum + 1 Jahr** (Status-Suffix `Proposed · expires <iso>`). Regeln:
   - **Refresh bei Wiedersichtung:** taucht dasselbe Pattern erneut auf (auch im *selben* Repo, was G1 nicht erfüllt), setzt `retro` `expires` neu auf +1 Jahr. Stetig wiederkehrende Patterns verfallen damit nie versehentlich.
   - **Weicher Verfall:** ist `expires < heute`, setzt `retro` den Status `Proposed → Expired` (Zeile **bleibt** — Audit-Trail + verhindert stumpfes Neu-Anlegen). Ein `Expired`-Eintrag zählt **nicht** mehr zur G1-Schwelle; taucht das Pattern danach erneut auf, wird der Eintrag reaktiviert (`Expired → Proposed`, frisches `expires`).
   - **Lazy Garbage Collection:** `retro` prüft/markiert abgelaufene Einträge zu Beginn **jedes** Laufs (es liest `LEARNINGS.md` ohnehin) — kein Cron.
   - **1 Jahr** ist der Default: großzügig genug, dass auch selten neu gebaute Projekttypen ein Zweit-Repo treffen, bevor die Evidenz verfällt; der Refresh-on-Resight + der weiche Verfall verhindern dennoch, dass das Register mit toten Einträgen anwächst.
2. **Provenance im PR-Body.** Der retro-PR-Body listet die Lesson-Quellen **namentlich**: Projekt-Name + Datei + Zeile, oder Projekt + PR-Nummer. Reviewer prüft die Quellen-Existenz als Hard-Check. Ohne Provenance → `CHANGES-REQUIRED`.
3. **Cooldown:** retro läuft max. 1× pro Woche pro Repo (oder per explizitem `/retro --force`-Trigger). Persistiert in der projekt-lokalen Datei `.claude/lessons/.retro-last-run` (ISO-Datum). **Amendment (2026-05-31):** ursprünglich war ein Lookup in `LEARNINGS.md`-Spalte „Datum" geplant; ersetzt durch dedizierte Datei, weil ein leerer retro-Lauf (kein Pattern reif für Promotion) keinen Ledger-Eintrag erzeugt — eine Cooldown-Quelle aus dem Ledger wäre für solche Läufe blind. Die `.retro-last-run`-Datei tickt deterministisch bei jedem Lauf.
4. **Reviewer-Gate bleibt.** Der retro-PR durchläuft denselben reviewer-Loop wie jeder andere PR — **kein Auto-Merge**, kein Bypass. Cross-Pack-Promotions (eine retro-Welle, die mehrere Packs trifft) werden gebündelt als **ein PR mit mehreren Regeln** (kein PR-Spam).

**Schreib-Hoheit.** `retro` schreibt **nur** in Sektion B (Anti-Patterns aus Einsatz) der Framework-/Build-Packs und ergänzt optional `Coder-Guidance` / `Reviewer-Checklist` / `Test-Approach`. Sektion A (Stable API & Deprecations) bleibt `train`-Hoheit — Berührung durch `retro` → reviewer `CHANGES-REQUIRED`.

**Cross-Pack-Bündelung.** Alle Promotions für denselben Pack in einem Cooldown-Fenster = **ein PR mit mehreren Regeln**. Promotions über mehrere Packs (z.B. ein Spring-Boot-Anti-Pattern UND ein Maven-Anti-Pattern in derselben Woche) bleiben **getrennt** (ein PR pro Pack) — sonst wird der Diff unübersichtlich und der reviewer-Loop verhakt sich an gemischten Themen.

### 9a. Sonar-Harvest — zweite Evidenz-Quelle (②)

`retro` hat neben den projekt-lokalen Lessons (Modus A) eine zweite Quelle: **statische Analyse-Findings** (SonarCloud/SonarQube) eines oder aller adoptierten Repos. Aufruf `/retro --sonar [<repo>|all]`. Begründung: Built-in-Sonar-Rules decken Fehlerklassen auf, die der `coder` systematisch macht; diese in die Packs zu spiegeln senkt die Findings künftiger Repos von Anfang an (Prävention statt Nach-Sanierung).

**Beziehung zu den zwei „Uhren".** Die *Analyse* (`sonar.yml`) läuft **pro Repo** periodisch — Fabrik-Default **monatlich (cron) + manuell (`workflow_dispatch`)**, KEIN push/PR-Trigger (spart Actions-Minuten; Details `knowledge/quality/sonar.md` §1a). Gewired vom `new-project`/`adopt`-Scaffold, sobald `profile.sonar.edition != none`; Voraussetzung Org-Secret `SONAR_TOKEN`. Der *Harvest* (dieser Abschnitt) läuft **fabrik-weit** mit eigener Kadenz: on-demand `/retro --sonar` und/oder periodischer `/schedule`-Sweep. Die beiden sind entkoppelt — die monatliche Analyse hält den Sonar-Stand aktuell, der Harvest erntet daraus, wenn genug Signal da ist.

**Maturity-Gate.** Repos ohne abgeschlossene Analyse oder mit < 20 Gesamt-Findings werden beim Harvest übersprungen (zu früh = Rauschen) — übersprungene Repos werden geloggt (kein stilles Verschlucken).

**Triage (a/b/c).** Pro Top-Rule: (a) Pack-Lücke → neue Coder-Guidance-Regel bzw. Sektion-B-Regel; (b) Enforcement-Lücke → Reviewer-Checklist-/Test-Approach-Zeile; (c) Skip. Kanonische **Skip-Klassen**: Domänen-/Naming-Rules (S100/S101/S116/S117 — oft fachlich gerechtfertigt), Style-/Cleanliness-Nits (S125/S1481/S1854/S1170), Upgrade-Churn (S2293 u.ä., vergeht beim nächsten Upgrade), Einzel-Logik-Bugs (im Projekt fixen, nicht generalisieren).

**G1-Sonar (ersetzt Schutzgitter #1 für diese Quelle).** Built-in-Rules sind bereits sprach-/framework-weit generalisiert (kein Projekt-Quirk), daher: **Mehr-Repo-Pfad** (Rule auf ≥2 Repo-Boards) ODER **Einzel-Repo-Pfad** (≥5× in 1 Repo + generische Built-in-Rule + User-getriggerter `/retro --sonar <repo>`). Schutzgitter #2 (Provenance: Repo + Rule-ID + count + Beleg-Issue-Keys), #3 (Cooldown, geteilte `.retro-last-run`) und #4 (Reviewer-Gate) gelten **unverändert**. Detail-Wiring: `agents/retro.md` → *Sonar-Harvest-Modus* (H1–H4).

---

## 10. Tester-Build-Dispatch

**Mechanismus.** Der `tester`-Agent wählt den Smoke-Befehl anhand `profile.build`. Detail-Wiring in `agents/tester.md` Abschnitt „Build-Tool-Tabelle" (kommt in PR-C, Welle 3 dieses Epics).

**Build-Tool-Tabelle (kanonisch — Single Source of Truth in dieser Spec):**

| `profile.build` | Smoke-Befehl |
|---|---|
| `maven` | `mvn -B -ntp -DskipTests=false verify` |
| `gradle` | `./gradlew build --no-daemon` |
| `npm` | `npm ci && npm test` |
| `pnpm` | `pnpm install --frozen-lockfile && pnpm test` |
| `uv` | `uv sync && uv run pytest -q` |
| `cargo` | `cargo test --all --locked` |
| `none` | skip; nur Sprach-Lint/Smoke aus `profile.test` (falls vorhanden) |

**Flags-Begründung (knapp):**

- `mvn -B -ntp` — batch mode + no transfer progress (CI-clean output).
- `./gradlew --no-daemon` — kein Daemon (one-shot, sauberer Exit).
- `npm ci` / `pnpm install --frozen-lockfile` — Lockfile-strict (kein Drift).
- `uv sync` — Lockfile-strict; `uv run pytest -q` — quiet mode.
- `cargo test --all --locked` — alle Crates, Lockfile-strict.

**Exit-Code-Semantik.** Tester wertet ausschließlich den Exit-Code (0 = PASS, ≠0 = FAIL). Build-Tool-spezifische Log-Pattern-Heuristik ist **out-of-scope** (zu fragil, sprach-übergreifend nicht stabil).

**Smoke-Pfad-Bedingung.** Wenn `profile.build = none`: kein Smoke gegen Build-Tool, sondern Fallback auf `profile.test` (z.B. ein direktes Skript-Smoke wie `bash test.sh`). Wenn auch das fehlt: `Test-Gate: SKIPPED-NO-BUILD` (analog `tester/R02` in LEARNINGS für DB-Smoke ohne Docker).

---

## 11. Backwards-Compat

Bestehende Projekte ohne `build` und `frameworks` im Profil sind ein häufiger Fall (alle Projekte vor diesem Epic). Verträgliche Behandlung:

1. **`build` fehlt** → Loader interpretiert als „kein Build-Pack laden". Tester nutzt Fallback aus `profile.test`. Adopt-Run beim nächsten `/adopt` setzt das Feld via Heuristik (§6).
2. **`frameworks` fehlt** → behandelt wie `frameworks: []`. Kein Framework-Pack wird geladen. Coder/Reviewer arbeiten nur mit Sprach-Pack + ggf. DB-Pack.
3. **`build` = leerer String** → identisch zu „fehlt" (defensiv).
4. **Migration der Bestandsprojekte** ist **opt-in**: `/adopt` führt die Detection beim nächsten Lauf durch — kein automatischer Mass-Update aller Bestandsprojekte.

**Reviewer-Toleranz.** Ein reviewer-Run, der ein Pack erwartet, das wegen Backwards-Compat nicht geladen ist, darf das **nicht** als `CHANGES-REQUIRED` werten — er muss klar im Review-Output kennzeichnen („Framework-Pack nicht geladen; Profil-Migration empfohlen") und sonst fortfahren.

---

## 12. Build-Wellen (Implementations-Reihenfolge dieses Epics)

| Welle | PR | Inhalt | Abhängigkeit |
|---|---|---|---|
| 1 (Spec) | **PR-A** | Diese Spec + `knowledge/_meta/versioning.md` | — |
| 2 (Schema + Loader + Train-CLI) | **PR-B** | Pack-Header-Schema, Pack-Loader-Logik (`coder`/`reviewer`/`tester`/`train`), `/train`-Resolver, leere Pack-Skelette | PR-A |
| 3 (Tester-Dispatch) | **PR-C** | `agents/tester.md` Build-Tool-Tabelle (§10), Smoke-Skript-Dispatch, `none`-Fallback | PR-B |
| 4 (Adopt + new-project Detection) | **PR-D** | `skills/adopt/SKILL.md` Framework/Build-Detection-Tabelle (§6) + Polyglott-Trigger (§7); `skills/new-project/SKILL.md` `--build` + `--framework` Flags + Fragen | PR-B |
| 5 (Pilot-Packs) | **PR-E** | `knowledge/frameworks/spring-boot-3.md`, `knowledge/build/maven.md`, ggf. java-Floor-Refinement | PR-B + PR-D |
| 6 (Retro 4 Schutzgitter) | **PR-F** | `agents/retro.md` mit Frequenz-Schwelle, Provenance-Pflicht, Cooldown, Reviewer-Gate (§9) | PR-B |

**Parallelisierbarkeit.** PR-C und PR-D können parallel zu PR-E laufen, sobald PR-B gemerged ist. PR-F ist unabhängig von PR-C/D/E und kann früher landen, sobald PR-B steht.

**Graceful Degradation (analog DB-Subsystem §14-Amendment).** Vorgezogene Wellen-Schritte (z.B. ein Skill-Edit vor dem zugehörigen Pack) müssen sich gegen fehlende Pack-Files **graceful** verhalten — klare Warn-Zeile, kein Hard-Fail. Detail-Begründung dort.

---

## 13. Nicht-Ziele P1

- **Kein eigener Agent pro Framework.** `coder` bleibt generisch — Framework-Wissen kommt via Pack-Selektion, nicht via Agent-Multiplikation. Spring-Boot-spezifische Coding-Disziplin ist eine Sektion im Spring-Boot-Pack, kein „spring-coder.md".
- **Keine harte 1:1-Bindung Framework=Sprache.** Spring-Boot kann Kotlin sein — der Pack ist primär Java-orientiert, aber dokumentiert die Kotlin-Eigenheiten in einem expliziten Abschnitt. `profile.lang: kotlin` + `profile.frameworks: [spring-boot@3]` ist valide.
- **Keine automatische Pack-Migration bei Framework-Major-Upgrade.** User bewusst editiert das Profil (`spring-boot@2` → `spring-boot@3`); Plugin folgt, fragt nicht zurück, schlägt aber bei fehlendem Pack laut auf (§5 Loader-Verhalten).
- **Cross-Sprach-Frameworks** (z.B. .NET-Pendants zu Spring) — eigener späterer Wellen-Schub. P1 deckt JVM- (Java/Kotlin), JS/TS-, Python- und Rust-Stacks ab.
- **Build-Tool-Plugin-Detection** (Maven-Plugins, Gradle-Plugins) — out-of-scope. Die Build-Pack-Wissensbasis dokumentiert Standard-Plugins kurz; tieferes Plugin-Wissen ist späterer Wellen-Schub.
- **Auto-Bump bei Framework-Patch-Releases** — `pack_version` ist intern, nicht an Framework-Releases gekoppelt; `train` triggert bei Bedarf, nicht automatisch bei jedem Patch.
