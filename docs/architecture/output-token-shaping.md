# ADR — Ausgabe-Token-Diät im Agenten-Flow (RTK-Mechanik selektiv, Spike S-065)

> **Ablage-Begründung:** `agent-flow` hat keine dedizierte `docs/adr/`-Konvention (geprüft per `ls docs/` + `grep -rl ADR docs/`). Der bestehende Ort für „ADR-Stil"-Entscheidungsdokumente ist `docs/architecture/*` (`docs/glossary.md`: *„architekt … bindende `docs/architecture.md` (ADR-Stil)"*), belegt durch die vorhandenen Subsystem-Docs (`metrics-subsystem.md`, `secrets-subsystem.md`, `board-cut-runbook.md` — letzteres ohne `-subsystem`-Suffix, also bereits kein starres Namensschema). Dieses Dokument folgt derselben Konvention, benannt nach der zugehörigen Spec-ID (`output-token-shaping`).
>
> **Status:** Entwurf (Spike-Ergebnis). Die Empfehlung ist **vorläufig, messungs-vorbehaltlich** — siehe §3 (AC4). Die gemessene Token-Ersparnis ist eine **offene Lücke** bis zur Ausführung des Mess-Protokolls (§2, AC3) in einer Folge-Story gegen ein echtes Konsum-Repo.
>
> **Bezug:** Spec [`docs/specs/output-token-shaping.md`](../specs/output-token-shaping.md) (AC1–AC6), dort insbesondere die AC1-Trennlinien-Tabelle (Klassifikation A/B/C + Signal-vs-Rauschen-Regeln), die die normative Grundlage dieses ADR ist.

---

## 1. Kontext (Zweck)

Die Arbeits-Agenten (`coder`, `reviewer`, `tester`, `cicd`) sind Bash-lastig; ein großer Teil des Token-Verbrauchs entsteht durch ungefilterte Befehls-Ausgaben. RTK (`rtk-ai/rtk`, Rust Token Killer) verspricht 60–90 % Ersparnis auf genau diesen Befehlen per PreToolUse-Hook. Gleichzeitig beruhen zwei harte Doktrin-Regeln des Frameworks auf **wörtlicher** Ausgabe: `coder/R02` und `reviewer/R01` (Verbatim-Pflicht bei Klassifikations-Widerlegung). Dieser Spike prüft, **ob und wo** die Mechanik selektiv im eigenen Flow sinnvoll ist — nicht, ob sie pauschal aktiviert wird.

## 2. AC2 — Weg C (Prompt-Ebene): Bestandsaufnahme + Empfehlungsliste

**Nur Empfehlung — kein Edit an `agents/*.md` in diesem Spike.**

### 2.1 Bereits vorhandene sparsame Praxis (Belege)

| Agent | Fundstelle | Was bereits sparsam ist |
|---|---|---|
| `cicd` | `agents/cicd.md` Abschnitt E, Schritt 2: `` gh run view <run-id> --repo "$repo" --log-failed `` | Zieht **nur** den fehlgeschlagenen Log-Ausschnitt, nicht den kompletten Run-Log. |
| `cicd` | `agents/cicd.md` A3, Schritt 7: `` docker logs "$app" --tail 50 `` | Tail-begrenzt statt vollständiges Container-Log. |
| `cicd` | `agents/cicd.md` „DB-Subsystem-Smoke": *„Trigger via `git diff --name-only` gegen die Merge-Basis"* | Nutzt die Datei**liste**, nicht den Volldiff, für die reine Pfad-Filter-Entscheidung. |
| `coder` | `agents/coder.md` `coder/R03`(b): `` git diff <base> -- <Datei> `` + `` grep -c "  it(" `` | Gezielter Diff auf **eine** Datei statt kumuliertem Diff; Testanzahl per Zähl-Grep statt Volltext-Auslesen. |
| `coder`/`reviewer` | `agents/coder.md` `coder/R07`, `agents/reviewer.md` `reviewer/R07`: `` grep -rn "<Name>" <src> `` | Gezielter Aufrufer-Grep statt Volldatei-Scan zum Beleg der Mount-Reachability. |
| `tester` | `agents/tester.md` §2a: `` jest --clearCache `` | Stack-spezifischer, gezielter Cache-Reset statt globalem Neu-Setup. |
| `cicd` | `agents/cicd.md` A2: `` gh run watch "$run_id" --repo "$repo" --exit-status `` | Bei grünem Run bereits knapp (kein Volltext-Log-Stream) — reiner Exit-Code-Wait. |

### 2.2 Konkrete Empfehlungsliste (Ergänzungen)

1. **`agents/reviewer.md` „Zuerst lesen" Punkt 1** (aktuell: *„`git diff` (kumuliert, unkomittiert) + geänderte Dateien in voller Datei"*, ohne Zwischenschritt): bei **großen** Diffs (Heuristik: `git diff --shortstat` > ~300 geänderte Zeilen) zuerst `git diff --stat` fahren, um Umfang/Dateiliste zu erfassen, danach den vollen Diff gezielt für die AC-relevanten Dateien ziehen — reine Lockfile-/generierte-Datei-Diffs müssen nicht vollständig durchgelesen werden. **Randbedingung:** der volle Diff bleibt für jede Datei Pflicht, die einen Critical/Important-Befund tragen könnte (Klasse-B-Signalregel aus AC1b gilt unverändert) — das ist nur eine vorgeschaltete Übersicht, keine Kürzung am eigentlichen Beleg.
2. **`agents/tester.md` §2 / Output-Format** (`Result:`/`Failures:`): implizit schon sparsam gedacht, aber keine explizite Anweisung gegen das Kopieren roher Volltext-Suite-Ausgabe ins Handoff. Ergänzungsvorschlag: *„Bei großen Suiten NICHT die volle Rohausgabe ins Handoff übernehmen — nur die Summary-Zeile (`X passed, Y failed`) + bei FAIL den/die betroffenen Failure-Block(e)."*
3. **`agents/coder.md` Punkt 6** (*„Betroffenen Code in voller Datei (nicht nur Diff-Kontext)"*) — **bewusst keine** Kürzungsempfehlung: das ist Korrektheits-kritisch (s. AC1-Tabelle, Sonderfall `cat`/`Read` auf Edit-Ziel-Dateien), bereits richtig restriktiv.
4. **`agents/reviewer.md` §4b-(c)** (*„per `grep` prüfen, ob ALLE Konsumenten…"*): wo nur Existenz/Anzahl der Konsumenten zählt (nicht der exakte Fundstellen-Kontext), `grep -rln` (Dateiliste) statt `grep -rn` (alle Treffer-Zeilen) erwägen — spart Tokens ohne Aussagekraft-Verlust, nur wenn die Zeile selbst kein Beleg werden muss.
5. **Generische Konvention „Zähl- statt Lies-Pflicht":** bislang nur reaktiv in `coder/R03` (Handoff-Claim-Selbstverifikation) verankert. Empfehlung: überall dort, wo im Befund/Handoff nur eine **Zahl** gebraucht wird (Testanzahl, Treffer-Anzahl, Zeilenanzahl), `grep -c`/`wc -l` statt Volltext-Ausgabe zu nutzen — beträfe potenziell auch `reviewer` (Zähl von `it(`-Blöcken bei `reviewer/R03`) und `tester` (Zähl von Failures) analog zu `coder/R03`.

## 3. AC4 — Entscheidung (Vorab-Empfehlung, vorläufig)

### 3.1 Optionen

- **A — Eigenbau:** generische Tricks (Dedup wiederholter Zeilen mit Count, Truncation-mit-Kontext) + Pack-verankerte, toolchain-spezifische Signal-Regeln (§5, AC6). Kein Fremd-Binary im Hot-Path.
- **B — RTK selektiv:** Fremd-Binary per PreToolUse-Hook, beschränkt auf die AC1-Allowlist (Klasse A).
- **C — nur Prompt-Ebene:** die in §2 gelistete Empfehlungsliste in die Agenten-Handoffs einziehen — kein Hook, kein Fremdcode.
- **Kombination.**

### 3.2 Vorab-Empfehlung: **C sofort + A mittelfristig**, B nur bedingt und zusätzlich

Begründung:

1. **RTKs Default deckt genau die Gate-kritischen Befehle am stärksten ein**, nicht die harmlosen: laut der vom Owner bereitgestellten Vergleichstabelle kürzt RTK `git diff` um −75 %, `cargo/npm/go test` + `pytest` um −90 %. Das ist exakt Klasse B — der Bereich, in dem gemäß AC1a **nur signal-erhaltend** gefiltert werden darf. RTKs README-Zusammenfassung nennt keine granulare Konfigurationsmöglichkeit pro Signal-Regel (nur vier globale Strategien: Smart Filtering, Grouping, Truncation, Deduplication) — es ist unklar, ob/wie sich RTK auf **nur** Klasse-A-Muster einschränken lässt, ohne die generischen Strategien (die laut Vergleichstabelle Klasse-B-Befehle mit-treffen) global zu deaktivieren. Das ist ein **Fidelity-Risiko**, das sich erst im Pilot (AC3) zeigt.
2. **Supply-Chain:** RTK ist ein Fremd-Binary, das laut Beschreibung *jeden* PreToolUse-Bash-Aufruf umschreibt — ein hochwertiges Angriffsziel (eine kompromittierte Version könnte nicht nur kürzen, sondern Befehle manipulieren). Weg A vermeidet Fremdcode im Hot-Path vollständig. Die Fakten zu RTK stammen aus einer Owner-bereitgestellten README-Zusammenfassung (Stand 2026-07) und sind in diesem Spike **nicht per WebFetch nachverifiziert** (kein WebFetch-Tool in diesem Coder-Lauf verfügbar) — Maintainer-Reputation/Update-Cadence/Release-Signierung sind **offene Prüfpunkte** vor einer B-Adoption.
3. **Weg A ist der natürliche Anschluss an AC6** (Pack-Verankerung): die Signal-Regeln leben ohnehin toolchain-spezifisch in den Packs (analog zum bestehenden `## Test-Approach`-Abschnitt) und werden über den bestehenden `train`/`retro`-Mechanismus gepflegt — kein neuer Prozess, kein neues Vertrauensproblem.
4. **Weg C ist risikofrei und sofort umsetzbar** (§2) — kein Hook, keine Fremd-Dependency, nur Prompt-Disziplin. Sollte als erste Maßnahme unabhängig vom A/B-Entscheid landen (separates Board-Item, falls der Owner zustimmt).
5. **Weg B bleibt optional offen**, aber NUR für Klasse-A-Befehle UND NUR wenn der Pilot (AC3, Folge-Story) eine positive Ersparnis **mit sauberer Pflicht-Gegenprobe** liefert — und selbst dann additiv, nicht als Ersatz für die Pack-Regeln aus Weg A.

### 3.3 Fidelity-Risiko-Bewertung

Klasse B (git diff, Test-/Build-Output) ist der eigentliche Risikoträger: eine zu aggressive Kürzung maskiert im schlimmsten Fall einen echten Gate-Fehlschlag (Review-/Test-Gate zeigt PASS, obwohl die Rohausgabe ein FAIL enthielt). Deshalb:
- Weg A beschränkt sich auf **konservative, generische** Tricks (Dedup identischer wiederholter Zeilen **mit Count**-Anzeige, Truncation **mit** Kontext — nie kommentarloses Abschneiden).
- AC3 verlangt eine **harte Pflicht-Gegenprobe** (Gate-Ergebnisse Baseline vs. RTK-Lauf müssen identisch sein) — jede Abweichung disqualifiziert den Piloten unabhängig von der gemessenen Ersparnis (Fidelity vor Ersparnis, E2-Prinzip der Spec).
- Klasse C (Verbatim-Quellen) bleibt in **jedem** Weg (A, B, C, Kombi) vollständig ausgenommen — das ist der bindende Vertrag der Spec.

### 3.4 Supply-Chain-Bewertung

RTK: Rust-Binary, Apache-2.0, laut den bereitgestellten Fakten „zero-dependency". Einzelnes Repo (`rtk-ai/rtk`), aus den gegebenen Fakten keine erkennbare Enterprise-/Foundation-Trägerschaft. **Nicht in diesem Spike verifiziert** (kein WebFetch): Anzahl Contributor, Release-Cadence, Signierung der Releases, CVE-Historie. Diese Punkte sind vor einer tatsächlichen B-Adoption (nach positivem Pilot) nachzuholen — als Auflage in einer Folge-Story, nicht rückwirkend für diesen Spike.

### 3.5 Telemetrie-aus-Verifikation

Laut den vom Owner bereitgestellten Fakten (RTK-README-Zusammenfassung, Stand 2026-07): Telemetrie ist **standardmäßig AUS** (opt-in). Bei Aktivierung werden ausschließlich anonyme Aggregat-Metriken übertragen (Command-Counts, Token-Savings, Ecosystem-Verteilung, Parse-Failures), 1×/Tag; explizit ausgeschlossen sind Quellcode, Dateipfade, Secrets und personenbezogene Daten. Das deckt sich mit der Secrets-Doktrin des Projekts (keine Pfade/Secrets/Quelltext-Exfiltration). **Herkunfts-Hinweis:** diese Aussage ist eine vom Owner bereitgestellte Zusammenfassung der Primärquelle (`github.com/rtk-ai/rtk` README) und wurde in diesem Spike **nicht selbst per WebFetch/curl gegen die Primärquelle nachverifiziert** (kein WebFetch-Tool verfügbar) — vor einer produktiven B-Adoption ist ein eigener Spot-Check gegen die Live-README fällig (`coder/R02`-Verbatim-Standard, falls die Aussage später als Klassifikationsgrundlage für einen Rollout-Entscheid zitiert wird).

### 3.6 Offene Lücke: gemessene Token-Ersparnis

**Nicht Teil dieses Spikes.** Die Vorab-Empfehlung in §3.2 ist **vorläufig, messungs-vorbehaltlich** — sie beruht auf AC1/AC2/AC6-Analyse, nicht auf einer tatsächlichen Messung in diesem Repo (`agent-flow` hat kein Konsum-Profil, s. §4). Erst nach Ausführung des Mess-Protokolls (§4) in einem echten Konsum-Repo (z. B. dev-gui) liegt eine belastbare Zahl vor; diese kann die Empfehlung zwischen A/B/Kombi verschieben, ändert aber nichts an der Denylist (Klasse C bleibt in jedem Fall unantastbar).

## 4. AC3 — Mess-Protokoll (reproduzierbar, **nicht ausgeführt** — needs real consumer repo)

> **needs real consumer repo.** `agent-flow` ist `language: md` mit No-Op-`build`/`test`/`lint` (`.claude/profile.md`) — es gibt keine Test-Runner-/Build-Ausgabe zum Eindampfen. Das folgende Protokoll ist präzise und reproduzierbar, wird aber in diesem Spike **nicht ausgeführt**: kein RTK-Install, keine erfundenen Zahlen. Ziel-Repo-Kandidat für die Ausführung: dev-gui (oder ein vergleichbares Konsum-Projekt mit echtem Build/Test/Lint). Die Ausführung ist Gegenstand einer **Folge-Story**.

### 4.1 Setup

1. **RTK-Install** im Ziel-Repo (nicht `agent-flow`): `rtk init -g` (Claude-Code-PreToolUse-Hook-Integration).
2. **Hook-Scope einschränken:** der Hook darf nur Klasse-A-Muster (AC1a-Tabelle) unbeschränkt filtern. Klasse B nur mit der jeweiligen Signal-Regel (AC1b); ist RTK selbst nicht granular genug konfigurierbar (offene Frage aus §3.2), Klasse B/C für den Piloten **deaktivieren/pass-through**, statt RTKs generische Default-Strategien auf Gate-kritische Befehle wirken zu lassen.
3. **Telemetrie-aus-Verifikation, VOR dem ersten Lauf:** Config-Status prüfen (z. B. `rtk config show` o. Ä., abhängig vom tatsächlichen CLI) und im Protokoll festhalten, dass Telemetrie deaktiviert ist. Zusätzlich: kein Netzwerk-Traffic zu einem RTK-Telemetrie-Endpunkt während des Piloten (Gegenprobe z. B. via Firewall-/Netzwerk-Log, falls im Zielsystem verfügbar).

### 4.2 Messgrößen

- `rtk gain` nach jedem `/flow`-Lauf (Ersparnis-Statistik je Befehlsklasse, falls das CLI das granular genug ausgibt).
- Token vor/nach je betroffenem Befehlsmuster: Baseline-Lauf (Hook aus) vs. Vergleichslauf (Hook an), gleicher/ähnlicher Story-Typ und -Größe, damit die Ersparnis nicht durch Story-Varianz verzerrt wird.
- `rtk discover`/`rtk session` als Zusatz-Diagnostik (welche Befehle tatsächlich gematcht/gefiltert wurden — Kontrolle gegen ungewollte Klasse-B/C-Treffer).

### 4.3 N ≥ 3 `/flow`-Läufe im Ziel-Repo

Mindestens ein Baseline-Lauf **ohne** Hook + mindestens zwei bis drei Läufe **mit** Hook (Allowlist Klasse A, s. 4.1.2), auf vergleichbaren Story-Größen (`size_est`), um Rausch-Varianz zu dämpfen.

### 4.4 Pflicht-Gegenprobe (hart)

Die `reviewer`-/`tester`-Gate-Ergebnisse (PASS/FAIL) müssen zwischen Baseline-Lauf und RTK-Lauf **identisch** sein — kein Fall, in dem eine gekürzte Ausgabe einen Befund maskiert, der im Baseline-Lauf ein FAIL/CHANGES-REQUIRED ausgelöst hätte. Bei Abweichung: **Pilot gilt als nicht bestanden**, unabhängig von der gemessenen Ersparnis (Fidelity vor Ersparnis, E2).

### 4.5 E1-Beobachtung (Parse-Fehler)

Während des Piloten explizit vermerken: wie oft (falls überhaupt) RTK bei einem Allowlist-Befehl einen Parse-Fehler wirft, und ob der Fail-Open-Pfad (Rohausgabe durchreichen statt leerer/abgeschnittener Ausgabe) tatsächlich greift.

### 4.6 Ergebnis-Template (in der Folge-Story auszufüllen)

| Lauf | Hook | Story-Größe | Tokens (roh) | Tokens (RTK) | Ersparnis % | Gate-Ergebnis (Review/Test) | Parse-Fehler? |
|---|---|---|---|---|---|---|---|
| 1 (Baseline) | aus | … | … | n/a | n/a | … | n/a |
| 2 | an | … | … | … | … | … | … |
| 3 | an | … | … | … | … | … | … |
| 4 | an | … | … | … | … | … | … |

## 5. AC5 — Scaffold-Schalter-Skizze (konditional, nicht implementiert)

Nur relevant, **falls** der spätere Pilot (§4, Folge-Story) positiv ausfällt:

- `new-project`/`adopt` bekommen einen optionalen Profil-Schalter, z. B. `token_shaping: rtk-hook | none` — **Default `none`**.
- Bei `rtk-hook`: das Scaffold legt eine minimal-scope PreToolUse-Hook-Config an, die **ausschließlich** Klasse-A-Muster (AC1a-Tabelle) matcht — Allowlist-basiert, nicht RTKs generischer Default (der laut §3.2 auch Klasse-B-Befehle aggressiv trifft).
- Klasse C (Denylist) wird **nie** Teil der Hook-Config, auch nicht optional aktivierbar.
- Telemetrie wird im Scaffold **explizit** deaktiviert (Defense-in-Depth — kein Vertrauen auf den externen Default, selbst wenn dieser laut §3.5 bereits aus ist).
- **Kein automatischer Install** des RTK-Binaries durch das Scaffolding selbst — der Owner/User installiert bewusst nach eigener Entscheidung, keine stille Fremd-Binary-Abhängigkeit in jedem neuen Projekt.

## 6. AC6 — Pack-Verankerung: Bewertung + Schema-Vorschlag (Weg-A-Pfad)

**Nur Bewertung + Schema-Vorschlag — kein Pack-Edit in diesem Spike.**

### 6.1 Bewertung

**Ja**, die toolchain-spezifischen Signal-vs-Rauschen-Regeln (AC1b) gehören in die Knowledge Packs (`knowledge/<lang>.md`):

- Sie sind bereits **stack-spezifisch** organisiert wie der bestehende `## Test-Approach`-Abschnitt (z. B. `knowledge/js.md` §„Test-Approach" behandelt bereits Jest-Cache-Fallen — ein artverwandtes, bereits etabliertes Muster).
- Sie sind der natürliche Ort für Wissen, das je Toolchain divergiert (`pytest`-Traceback-Format ≠ `cargo test`-Panic-Format).
- `train` hält Packs bereits über den etablierten PR+Gate-Mechanismus mit Quellenpflicht + stabilen Regel-IDs aktuell (`agents/train.md` Schritt 4: *„jede Regel mit autoritativer Quelle (Link) + stabiler ID"*) — ein neuer Output-Contract-Abschnitt fügt sich ohne neuen Prozess ein.
- `retro` hebt projekt-lokale Tier-1-Lessons (aus `reviewer`/`tester`-Write-back) via PR+Gate ins globale Pack — derselbe Mechanismus greift 1:1 für Fehlklassifikationen aus einem künftigen Piloten (s. 6.3).

### 6.2 Schema-Vorschlag (maschinenlesbar)

Neuer Unterabschnitt `## Output-Contract` je Sprach-Pack (analog zur bestehenden Sektions-Hierarchie `## Coder-Guidance` / `## Reviewer-Checklist` / `## Test-Approach`), mit festem, tabellarischem Format + Versionsanker (analog zur `schema_version`-Konvention aus `.claude/metrics/baseline.json`, `docs/architecture/metrics-subsystem.md` §2.3):

```markdown
## Output-Contract
<!-- schema_version: 1 -->
| Befehlsmuster | Klasse | Behalten (Signal) | Kürzen (Rauschen) | Regel-ID |
|---|---|---|---|---|
| `pytest` | B | Traceback + Assertion-Diff + Summary-Zeile | grüne PASSED-Zeilen, Progress-Punkte, Timing | `py/OC01` |
| `ruff check` | B | jede Verstoß-Zeile (Datei:Zeile:Spalte + Regel-ID) | bei grün: nichts zu kürzen | `py/OC02` |
```

- **Spalten fest** (Befehlsmuster, Klasse A/B/C, Behalten, Kürzen, Regel-ID) — ein künftiger Weg-A-Filter (oder ein Agent, der die Kürzung selbst vornimmt statt eines externen Parsers) kann die Tabelle zeilenweise auswerten.
- **Regel-ID-Namespace `<lang>/OC<NN>`** (Output-Contract) — eigene Präfix-Familie, getrennt von `<lang>/R<NN>` (Coder-Guidance-Regeln) und `<pack>/A<NN>` (Framework-Pack, train-Land), damit ein künftiger maschineller Konsument gezielt nur die OC-Zeilen parsen kann, ohne die restliche Pack-Prosa zu berühren.
- **`schema_version`-Kommentar** direkt unter der Sektions-Überschrift — ermöglicht künftige Migrations-Checks in Konsumenten, exakt wie beim Metrik-Baseline-Schema.

### 6.3 Anbindung an `train` und `retro`

- **`train`:** Der `## Output-Contract`-Abschnitt wird wie jeder andere Pack-Abschnitt behandelt — ändert sich ein Test-Runner-CLI-Ausgabeformat (z. B. ein neues `pytest`-Major mit geändertem Traceback-Layout), löst das eine reguläre `/train <lang>`-Aktualisierung der betroffenen OC-Zeile aus, mit Quelle + Regel-ID wie gewohnt (kein neuer Prozess).
- **`retro`:** Der bestehende Tier-1-Write-back-Pfad (`reviewer`/`tester` schreiben Befunde nach `.claude/lessons/coder.md`, `retro` hebt sie global) wird um einen zusätzlichen Auslöser erweitert: erkennt ein künftiger Pilot (§4) einen maskierten Gate-Fehlschlag (Pflicht-Gegenprobe schlägt fehl) **oder** eine Fehlklassifikation (ein als Klasse A eingestufter Befehl erweist sich als Gate-relevant), wird das als projekt-lokale Lesson in `.claude/lessons/coder.md` festgehalten und über den bestehenden `retro`-PR+Gate-Mechanismus in den `## Output-Contract`-Abschnitt des betroffenen Packs gehoben — exakt derselbe Tier-1→Tier-2-Mechanismus wie für alle anderen Coder-Regeln, kein Sonderpfad nötig.

---

## Zusammenfassung (Verweis)

- **Denylist (Klasse C)** ist bindend und unabhängig vom gewählten Weg — s. Spec-Verträge.
- **Vorab-Empfehlung:** C sofort + A mittelfristig (Pack-Verankerung), B optional/additiv nach positivem Pilot.
- **Offene Lücke:** gemessene Token-Ersparnis — Folge-Story gegen ein echtes Konsum-Repo (z. B. dev-gui), Protokoll s. §4.
