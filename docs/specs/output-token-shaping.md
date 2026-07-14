---
id: output-token-shaping
title: Ausgabe-Token-Diät im Agenten-Flow — Spike RTK-Mechanik selektiv anwenden
status: active
area: flow-orchestrierung
version: 1
spec_format: use-case-2.0
---

# Spec: Ausgabe-Token-Diät im Agenten-Flow  (`output-token-shaping`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für die Spike-Abarbeitung: Dies ist ein **Untersuchungs-Item (Spike)** — die Acceptance-Kriterien sind **Entscheidungs-/Ergebnis-Artefakte** (Klassifikation, Pilot-Messung, ADR), nicht ein Produktiv-Feature. Kein Produktiv-Hook wird im Spike scharfgeschaltet.

## Zweck
Die Arbeits-Agenten (`coder`, `reviewer`, `tester`, `cicd`) sind stark Bash-lastig (Git, Tests, Build, Docker, `grep`/`ls`/`find`). Ein großer Teil des Token-Verbrauchs entsteht durch **Befehls-Ausgaben**, die ungefiltert in den Kontext fließen. Das Projekt **RTK (Rust Token Killer, `rtk-ai/rtk`)** filtert/gruppiert/kürzt/dedupliziert solche Ausgaben transparent per PreToolUse-Hook und verspricht 60–90 % weniger Tokens auf genau diesen Befehlen.

RTK greift jedoch nur **partiell** sinnvoll: Manche unserer Ausgaben **müssen wörtlich und ungekürzt** bleiben, weil harte Doktrin-Regeln darauf beruhen — `coder/R02` und `reviewer/R01` (Verbatim-Pflicht bei Klassifikations-Widerlegung) sowie die Treue der `reviewer`-/`tester`-Gates. Owner-Ziel (2026-07-14): Prüfen, ob wir die **Mechanik selektiv im eigenen Flow hinterlegen** — nur an den Befehlen, wo Fidelity-Verlust billig ist, und dort roh lassen, wo Korrektheit zählt.

**Verfeinerung (2026-07-14, aus RTK-Vergleichstabelle):** Die Trennlinie ist **nicht binär pro Befehl**. Die RTK-Tabelle dampft gerade die Gate-kritischen Befehle am stärksten ein (`git diff` −75 %, `cargo/npm/go test` + `pytest` −90 %, `cat/read` −70 %). Das zeigt: Die richtige Frage ist nicht *ob* ein Befehl gefiltert wird, sondern *was* dabei wegfällt — **Signal behalten** (Test-Failures, Assertion-Diff, erste Fehlerzeile, geänderte Diff-Hunks) vs. **Rauschen kürzen** (grüne Zeilen, Fortschrittsbalken, Timing, Duplikate). Was „Signal" ist, ist **toolchain-spezifisch** (`pytest` ≠ `cargo test` ≠ `go test` ≠ `eslint`) — und dieses Wissen liegt strukturell bereits in `knowledge/<lang>.md`. Damit ist der **Knowledge Pack der natürliche Ort** für die Eindampf-Regeln, und **Weg A (Eigenbau)** wird attraktiver: kein generischer Fremd-Filter, sondern pro Pack ein kleiner „Output-Contract".

## Acceptance-Kriterien

- **AC1 — Trennlinie (Herzstück, zweistufig).** (a) **Grobklassifikation** der Bash-Befehle in **„gefahrlos filterbar"** (Exploration: `ls`, `find`, `grep`, `git status`, `git log`, `tree`, `docker ps`) vs. **„nur signal-erhaltend filterbar"** (`git diff`, Test-Runner-Output, Build-/Lint-Logs — speist die `reviewer`-/`tester`-Gates + Verbatim-Belege `coder/R02`/`reviewer/R01`) vs. **„nie filtern"** (alles, was direkt einen wörtlichen Klassifikations-Beleg liefert). (b) Für die mittlere Klasse: pro Toolchain die **Signal-vs-Rauschen-Regel** benennen (was behalten, was kürzen), damit auch Tests/Diffs eindampfen dürfen, **ohne** das Gate-relevante Signal zu verlieren. Ergebnis: eine Tabelle in dieser Spec bzw. im ADR. Grenzfälle (z. B. `git show` = Diff-artig) explizit zugeordnet (im Zweifel restriktiver).
- **AC2 — Weg C sofort (Prompt-Ebene, risikofrei).** Bestandsaufnahme, welche Agenten-Handoffs (`agents/*.md`) schon sparsame Befehlswahl vorgeben, und eine konkrete Empfehlungsliste für Ergänzungen (z. B. `git diff --stat` vor vollem Diff, `grep -c`, gezielte Datei-Reads statt ganzer Dateien). **Nur Empfehlung, kein Edit im Spike.**
- **AC3 — Weg B Pilot als reproduzierbares Mess-Protokoll (Owner-Entscheidung 2026-07-14: Protokoll statt Messung).** In diesem md-Repo (`language: md`, No-Op-`build`/`test`) gibt es **keine** Test-Runner-/Build-Ausgaben zum Eindampfen — ein aussagekräftiger Pilot braucht ein **echtes Konsum-Projekt** (z. B. dev-gui). AC3 liefert daher **kein** installiertes Binary und **keine** erfundenen Zahlen, sondern ein **präzises, reproduzierbares Mess-Protokoll**: (a) Setup (RTK-Install-Weg, PreToolUse-Hook beschränkt auf die AC1-Allowlist, Telemetrie-aus-Verifikation), (b) Messgrößen (`rtk gain` je Befehlsklasse, Token vor/nach), (c) N ≥ 3 `/flow`-Läufe im Ziel-Repo, (d) **Pflicht-Gegenprobe**: `reviewer`/`tester`-Gate-Ergebnisse (PASS/FAIL) bleiben gegenüber einem Baseline-Lauf **unverändert** — kein maskierter Fehlschlag durch gekürzte Ausgabe. Explizit vermerkt: **needs real consumer repo** (agent-flow ist als Ziel ungeeignet). Die tatsächliche Ausführung ist Sache einer Folge-Story.
- **AC4 — Entscheidung als ADR (Entwurf, Zahlen offen bis AC3-Ausführung).** Ergebnis-Report mit begründeter, aus AC1/AC2/AC6 ableitbarer **Vorab-Empfehlung** zwischen **A** (Mechanik selbst nachbauen, nur generische Tricks: Dedup/Truncation-mit-Kontext, plus Pack-Verankerung aus AC6), **B** (RTK-Binary selektiv), **C** (nur Prompt-Ebene) oder einer **Kombination**. Enthält: Fidelity-Risiko-Bewertung, Supply-Chain-Bewertung des Fremd-Binaries und **Verifikation aus der RTK-Doku, dass die Telemetrie standardmäßig aus ist** (passt zur Secrets-Doktrin: keine Pfade/Secrets/Quelltext exfiltriert). Die **gemessene** Token-Ersparnis bleibt als ausdrücklich markierte Lücke offen, bis das AC3-Protokoll im Konsum-Repo ausgeführt wurde — die ADR-Empfehlung ist bis dahin als „vorläufig, messungs-vorbehaltlich" gekennzeichnet.
- **AC5 — Scaffold-Schalter-Skizze (bedingt, konditional formuliert).** Für den Fall, dass der spätere AC3-Pilot (Folge-Story) positiv ausfällt: Skizze, wie ein **optionaler, standardmäßig AUS**-Schalter im `new-project`-/`adopt`-Scaffold aussähe — mit der Allow-/Denylist aus AC1 als Kern und Telemetrie-aus als Default. **Umsetzungsvorschlag, nicht implementiert.**
- **AC6 — Pack-Verankerung der Eindampf-Regeln (Weg-A-Pfad).** Bewerten und im ADR dokumentieren, ob die **toolchain-spezifischen Signal-vs-Rauschen-Regeln** (aus AC1b) in die Knowledge Packs `knowledge/<lang>.md` gehören — als kleiner, einheitlicher **„Output-Contract"**-Abschnitt pro Pack (Test-/Build-/Lint-Ausgabe: was ist Gate-relevantes Signal, was ist kürzbares Rauschen). Prüfen: (a) ein einheitliches Schema für diesen Abschnitt (damit ein Filter — Weg A — es maschinell lesen kann); (b) Anbindung an `train` (hält die Regeln beim Toolchain-Update aktuell) und `retro` (eine Fehlklassifikation/ein maskierter Gate-Fehlschlag im Pilot ⇒ Pack-Korrektur). **Nur Bewertung + Schema-Vorschlag im Spike, kein Pack-Edit.**

## Trennlinien-Tabelle (AC1 — das eigentliche Artefakt des Spikes)

### AC1a — Grobklassifikation

| Klasse | Beispiel-Befehle | Begründung |
|---|---|---|
| **A — gefahrlos filterbar** (reine Exploration, keine Gate-/Klassifikations-Funktion) | `ls`, `tree`, `find`, `grep`/`rg` (Fundstellen-Suche, nicht Beleg-Zitat), `git status`, `git log` (Historie überfliegen, s. Ausnahme unten), `docker ps`, `docker images`, `kubectl get`, `npm ls`/`pip list` (Abhängigkeits-Übersicht) | Ergebnis dient nur der Orientierung des Agenten selbst — fließt in keinen PR-Comment, kein Gate-Urteil, keinen Verbatim-Beleg ein. Kürzung/Gruppierung/Dedup kostet keine Korrektheit. |
| **B — nur signal-erhaltend filterbar** (Mittelklasse — speist `reviewer`-/`tester`-Gate, ggf. Verbatim-Beleg) | `git diff` (kumuliert/pro Datei), Test-Runner-Output (`pytest`, `cargo test`, `go test`, `jest`/`npm test`), Lint-/Build-Output (`eslint`, `ruff check`, `tsc`, `next build`), Paket-Install-Logs (`npm install`, `pip install`, `bundler install`) | Ergebnis fließt direkt in eine Gate-Entscheidung (Review-Gate, Test-Gate) oder eine AC-Abgleich-Aussage ein — Fidelity-Verlust maskiert im schlimmsten Fall einen echten Fehlschlag (Kern-Sorge der AC3-Pflicht-Gegenprobe). Kürzbar, aber **nur** unter der toolchain-spezifischen Signal-Regel (AC1b) — nie das Gate-relevante Signal selbst. |
| **C — nie filtern** (Denylist) | jeder Bash-Aufruf, dessen **rohe stdout** als **wörtliches Zitat** (Blockquote + Anchor-Link) in einen PR-Comment zur Stützung/Widerlegung eines Klassifikations-Befunds einfließt (`coder/R02`, `reviewer/R01`) — typisch `curl <primärquelle>` als Spot-Check-Ersatz für WebFetch; sowie `git show` (Grenzfall, s. E2) | Genau der Text muss 1:1 erhalten bleiben, sonst ist der Anchor-Beleg wertlos bzw. das Zitat unbelegt (`coder/R02` verbietet dann sogar den Re-Push). Ein Filter, der hier auch nur ein Zeichen ändert (z. B. Dedup eines vermeintlich „identischen" Absatzes), zerstört die Beweiskraft. |

**Sonderfall `cat`/`Read` (kein RTK-Beispiel in AC1a, aber Teil des `coder`-Alltags):**

| Kontext | Klasse | Begründung |
|---|---|---|
| Datei, die der Agent **anschließend editiert** (deckt `agents/coder.md` „Betroffenen Code in voller Datei (nicht nur Diff-Kontext)") | **B, restriktiv gehandhabt** (praktisch wie „nie kürzen", solange kein reiner Vendor-/Lockfile-Inhalt) | Kommentare/Docstrings können load-bearing sein (Invarianten, Security-Hinweise) — die generische RTK-Heuristik „Kommentare weg" ist hier falsch kalibriert. Ausnahme: rein generierter/vendorer Code (z. B. `package-lock.json`) darf ohne Korrektheits-Risiko gekürzt werden. |
| Datei, die nur zur **Orientierung** gelesen wird (nicht Edit-Ziel, z. B. Nachbar-Modul zum Verständnis) | **A** | Reine Exploration, kein Korrektheits-Risiko. |

**Grenzfälle (E2, im Zweifel restriktiver zugeordnet):**
- `git show` → **Klasse C** (Diff-artig, kann eine spezifische Commit-Historie 1:1 belegen — explizit so in E2 benannt).
- `git log` → bleibt **Klasse A**, solange er nur der Übersicht dient. **Ausnahme:** wird eine einzelne Commit-Message aus dem Log wörtlich als Beleg zitiert, gilt für **genau diesen Aufruf** Klasse C.

### AC1b — Signal-vs-Rauschen-Regel je Toolchain (Klasse B)

| Toolchain | Behalten (Signal) | Kürzen (Rauschen) |
|---|---|---|
| `git diff` | geänderte Hunks komplett (± unmittelbarer Kontext), Datei-Header (`diff --git`, `+++`/`---`), Rename/Delete-Markierungen | über den Hunk-Rahmen hinausgehende unveränderte Kontextzeilen; bei sehr langen generierten Diffs (Lockfiles) ggf. `--stat`-Zusammenfassung statt Volltext — nur wenn keine AC-relevante Logik im Lockfile liegt |
| `pytest` | vollständiger Traceback jedes Failures, Assertion-Diff (`assert … == …`), erste Fehlerzeile, Summary-Zeile (`X passed, Y failed`) | einzelne grüne `PASSED`-Zeilen, Fortschrittspunkte (`....`), Timing pro Test, nicht-Gate-relevante Warnings |
| `cargo test` | `FAILED`-Block mit Panic-Message + Zeile, `test result: … failed` Summary | `test … ok`-Zeilen, Compile-Fortschritt (`Compiling`, `Finished`), Timing |
| `go test` | `--- FAIL:`-Block komplett inkl. `Error Trace`/`Error`-Diff, `FAIL`-Summary | `--- PASS:`-Zeilen, `ok  	pkg	0.003s`-Zeilen bei durchweg grün (nur Gesamt-Summary behalten) |
| `jest`/`npm test` | `●`-Fail-Block komplett (Expect-Diff + Stack bis zum ersten App-Frame), abschließende Summary (`Tests: X failed, Y passed`) | `✓`-Zeilen, Coverage-Tabelle (sofern nicht AC-Gegenstand), Drittbibliotheks-`console.log`-Rauschen |
| `eslint`/`ruff check` | bei **rot**: jede Verstoß-Zeile (Datei:Zeile:Spalte + Regel-ID + Message) — das IST bereits das Signal, hohe Dichte, kaum Rauschen → **nichts kürzen**; bei **grün**: nur die Summary-Zeile | bei grün: ohnehin nur 1 Zeile Output, keine Kürzung nötig |

## Verträge
- **Trennlinie ist bindend (präzisiert gemäß der obigen AC1a-Dreiklassen-Tabelle):** Egal ob Weg A oder B gewählt wird — die **echte Denylist** („nie filtern", Klasse C) ist auf **wörtliche Klassifikations-Belege** beschränkt (externe Primärquellen-Zitate für `coder/R02`/`reviewer/R01`, inklusive `git show` als Grenzfall). `git diff` und Test-/Build-Output sind **Klasse B** (Mittelklasse, „nur signal-erhaltend filterbar") — sie dürfen gekürzt werden, aber **nur** unter der jeweiligen toolchain-spezifischen Signal-Regel (AC1b); das Gate-relevante Signal darf dabei **nie** verloren gehen. Diese Tabelle ist das eigentliche Artefakt des Spikes.
- **Hook wirkt prozessweit, nicht pro Agent:** In Claude Code entscheidet ein PreToolUse-Hook anhand des **Befehls-Musters**, nicht anhand des aufrufenden Agenten. „Nur wo nötig" = „nur bei den richtigen Befehlen".

## Edge-Cases & Fehlerverhalten
- **E1 — Parse-Fehler von RTK:** Reißt RTK bei einem Allowlist-Befehl (unerwartetes Format), MUSS die **Roh-Ausgabe** durchgereicht werden (fail-open), nie eine leere/abgeschnittene. Im Pilot beobachten und im ADR vermerken.
- **E2 — Grenzfall-Befehl doppeldeutig** (z. B. `git show` = Diff-artig): im Zweifel der **Denylist** zuordnen (Fidelity vor Ersparnis).

## NFRs
- Der Spike selbst ändert **keinen** Produktivpfad (keine Hooks scharf, keine Fremd-Dependency dauerhaft aufgenommen, kein Binary-Install). Deliverable ist Doku + reproduzierbares Mess-Protokoll + ADR-Entwurf.

## Nicht-Ziele
- Kein produktiver PreToolUse-Hook im Spike-Umfang.
- Keine dauerhafte Aufnahme des RTK-Binaries ohne positive Messung.
- Keine Änderung der Verbatim-Doktrin (`coder/R02`, `reviewer/R01`) — sie ist die Randbedingung, nicht der Verhandlungsgegenstand.
- Kein Nachbau der 100+ befehlsspezifischen RTK-Parser (nur generische Tricks stehen bei Weg A zur Debatte).

## Abhängigkeiten
- `agents/coder.md`, `agents/reviewer.md`, `agents/tester.md` (Handoff-Verträge, Verbatim-Regeln — Randbedingung für AC1/AC2).
- `knowledge/<lang>.md` (Ziel der Pack-Verankerung, AC6), `agents/train.md` + `agents/retro.md` (Pflege-/Lernpfad der Eindampf-Regeln).
- `skills/new-project/SKILL.md`, `skills/adopt` (Scaffold-Ziel für AC5).
- Externe Quelle: `rtk-ai/rtk` (Apache-2.0).
