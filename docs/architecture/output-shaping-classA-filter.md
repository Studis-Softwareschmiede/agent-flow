# ADR — Weg A: Eigenbau-Filter für Klasse-A-Befehle (Design-first, S-067)

> **Ablage-Begründung:** analog zum Eltern-ADR [`output-token-shaping.md`](output-token-shaping.md) — `agent-flow` hat keine dedizierte `docs/adr/`-Konvention; „ADR-Stil"-Entscheidungen leben unter `docs/architecture/*`, benannt nach der Spec-ID (hier `output-shaping-classA-filter`).
>
> **Status:** **Design-Entscheidung (bindend als Constraint für die spätere Umsetzungs-Story), Umsetzung ausstehend bis Owner-Freigabe.** Kein Filter-Code in dieser Story.
>
> **Bezug:** Spec [`docs/specs/output-shaping-classA-filter.md`](../specs/output-shaping-classA-filter.md) (AC1–AC5). Eltern-ADR [`output-token-shaping.md`](output-token-shaping.md): §3.0 (Pilot-Befund S-345), §3.3 (Fidelity), §6 (Output-Contract-Schema). Grobklassifikation A/B/C: [`docs/specs/output-token-shaping.md`](../specs/output-token-shaping.md) „Trennlinien-Tabelle" (AC1a/AC1b) — **normative Grundlage**, hier nicht wiederholt.
>
> **Verwandt:** `[[output-shaping-prompt-frugality]]` (Weg C, umgesetzt S-066 — die risikofreie Prompt-Ebene). Weg A ist der mittelfristige, mechanische Ausbau **nur** für Klasse A.

---

## 1. Kontext und Problem

Der Eltern-ADR (§3.0) hat messungs-belegt: der reale, sichere Token-Nutzen (~65–80 %) sitzt in **Klasse-A-Explorationsbefehlen** (`ls`, `find`, `grep`, `git status`, `git log`, `docker ps` …) — Ausgaben, die nur der Orientierung des Agenten dienen und in **kein** Gate, **keinen** PR-Comment, **keinen** Verbatim-Beleg fließen. Weg B (RTK als Fremd-Binary im PreToolUse-Hook) wurde **abgelehnt**: seine naive Tail-Heuristik hat auf Test-Ausgabe (Klasse B) das Fehlersignal still verloren, und die Supply-Chain war Hot-Path-untauglich.

**Die zentrale Lehre — und der Kern dieses Designs:** RTKs Fehler war **nicht** „schlechte Heuristik", sondern **die Position des Filters**. Als prozessweiter PreToolUse-Hook lag RTK im Hot-Path **jedes** Bash-Aufrufs — auch der Gate-kritischen (`git diff`, `pytest`). Ob eine Gate-Ausgabe verfälscht wurde oder nicht, hing allein davon ab, dass eine Matching-Regel den Befehl korrekt als „nicht filtern" einstufte. Die Sicherheit war **verhaltensbasiert** (korrektes Matching), nicht **strukturell** (physische Unfähigkeit, Klasse B zu berühren).

**Problem dieser Story:** Wie fangen wir den Klasse-A-Nutzen mechanisch ein, **ohne** den Filter je in eine Position zu bringen, in der er Klasse-B/C-Ausgabe überhaupt sehen kann? Die Design-Frage ist nicht „wie kürzen", sondern „wie garantieren, dass Klasse B/C **strukturell** nie durch den Filter läuft".

---

## 2. AC1 — Mechanismus-Entscheidung

### 2.1 Optionen

- **Opt-Hook — PreToolUse-Hook, prozessweit, Command-Muster-basiert.** Ein Hook fängt jeden Bash-Aufruf ab, klassifiziert per Regex/Allowlist und transformiert nur bei Klasse-A-Treffern. (RTKs Mechanik, mit eigenem Code.)
- **Opt-Wrapper — expliziter Wrapper-Befehl.** Der Agent ruft **bewusst** `shape <klasse-A-befehl>` — der Filter läuft **nur**, wenn er explizit vorangestellt wird. Bare Befehle (der Default für **alles**, inkl. jeder Klasse B/C) laufen nie durch den Filter.
- **Opt-Konvention — reine Prompt-Disziplin.** Kein Werkzeug; die Agenten kürzen ihre Ausgabe „im Kopf". → Das **ist** bereits Weg C (`[[output-shaping-prompt-frugality]]`, S-066); als eigener Weg-A-Mechanismus fällt diese Option in sich zusammen und liefert keinen mechanischen, reproduzierbaren Effekt. Sie wird hier nicht weiter als eigenständige Weg-A-Option geführt.

### 2.2 Abwägung (die vier Spec-Kriterien)

| Kriterium | Opt-Hook (prozessweit) | **Opt-Wrapper (explizit)** |
|---|---|---|
| **Fidelity-Garantie Klasse B/C** | Nur **verhaltensbasiert**: der Filter liegt im Hot-Path **jedes** Befehls; dass `git diff`/`pytest` unangetastet bleiben, hängt an korrektem Matching. Genau RTKs Fehlerklasse. Compound-Befehle (`ls && git diff`) sind pattern-basiert prinzipiell unzuverlässig klassifizierbar. | **Strukturell:** der Filter ist nur im Pfad, wo er explizit vorangestellt wurde. Ein bare `git diff` läuft physisch nie durch den Wrapper — es gibt keine Regel, die falsch matchen könnte, weil es keine Interzeption gibt. |
| **Wirkungsradius bei Fehlern** | Ein Bug im Matcher/Transform trifft **potenziell jeden** Befehl — inkl. Gate-Ausgaben (still, unsichtbar im Transkript). Maximaler Radius. | Ein Bug trifft **nur** explizit gewrappte (= Klasse-A-)Befehle. Kein Gate wird von Klasse A gespeist → Worst Case ist „falsche Explorations-Ausgabe → Agent führt bare neu aus". Minimaler Radius. |
| **Wartbarkeit** | Muss Compound-Befehle, Pipes, Shell-Verkettung, Subcommand-Varianten (`git status` vs. `git diff`) robust auseinanderhalten — die schwierige, fehleranfällige Klassifikationslogik lebt im Hot-Path. | Klassifikation entfällt weitgehend: der Agent wählt Klasse A durch die bewusste Voranstellung. Der Wrapper braucht nur eine **geschlossene, kompilierte Allowlist** als zweite Barriere. Kleiner, gut testbarer Kern. |
| **Nachvollziehbarkeit** | Shaping ist **unsichtbar**: das Transkript zeigt `git diff`, die Ausgabe wurde still verändert. Exakt das Muster von CVE-2026-45792 (stille Verfälschung der dem LLM gezeigten Ausgabe). | Shaping ist **explizit im Transkript**: `shape ls -la` zeigt jedem Leser genau, welche Ausgaben mechanisch bearbeitet wurden. Auditierbar per Definition. |

### 2.3 Entscheidung: **Opt-Wrapper (expliziter, opt-in Wrapper-Befehl)**

**Empfehlung: Wrapper-Befehl** (Arbeitsname `shape`), opt-in pro Aufruf, mit interner Allowlist, fail-open, nur generische Transforms. Begründung in einem Satz: **Der Wrapper macht die Klasse-B/C-Unversehrtheit zu einer Eigenschaft der Architektur (der Filter ist nicht im Pfad) statt zu einer Eigenschaft des Filter-Verhaltens (der Filter matcht korrekt)** — das ist die direkte, strukturelle Antwort auf die RTK-Lehre aus §1.

Ein entscheidender Zweit-Effekt: das **Fehlerverhalten der Adoption** ist fail-safe. Vergisst ein Agent, einen Klasse-A-Befehl zu wrappen, bekommt er die volle Rohausgabe (kein Nutzen, aber **null** Fidelity-Verlust). Beim Hook ist das Fehlerverhalten fail-dangerous: matcht die Regel einen Klasse-B-Befehl versehentlich als Klasse A, wird ein Gate still verfälscht. Fail-safe-Adoption schlägt fail-dangerous-Adoption — das ist der ausschlaggebende Trade-off.

Der Preis (Agent muss die Voranstellung bewusst setzen) ist gering: Weg C (S-066) hat die Sparsamkeits-Disziplin in den Handoffs bereits etabliert — dort primär für Klasse-B-nahe Sparsamkeit (`git diff --stat` vor Volldiff, `grep -rln`/`-c`, `wc -l`), **nicht** bereits als explizite AC1a-Klasse-A-Wrapper-Liste. Die konkrete Benennung der zu wrappenden Klasse-A-Befehle ist daher Teil der Adoptions-Story (Prompt-Ergänzung in `agents/*.md`), die **nach** bestandenem Fidelity-Test (§6) und pro Befehl opt-in erfolgt; Weg C liefert dafür die eingeübte Grundhaltung, nicht die fertige Liste.

---

## 3. AC2 — Klasse-B/C-Schutz als harte, strukturelle Invariante

Die Garantie „`git diff`, Test-/Build-Output und Verbatim-Quellen laufen **nie** durch den Filter" ruht auf **zwei voneinander unabhängigen Barrieren** (Defense-in-Depth) — jede allein genügt:

**Barriere 1 — Invocation-Boundary (primär, strukturell).** Der Filter existiert nur im Ausführungspfad eines Befehls, dem `shape` explizit vorangestellt wurde. Alles andere — und das ist der **Default für ausnahmslos jede** Klasse B und C — wird bare ausgeführt und sieht den Wrapper nie. Das ist keine Regel, der der Filter folgt, sondern die **Abwesenheit** des Filters aus dem Pfad. Die Prompt-Ebene stellt sicher, dass `shape` **nur** vor Klasse-A-Befehle gesetzt wird.

**Barriere 2 — interne, geschlossene Allowlist (sekundär, für den Fall einer falschen Voranstellung).** Selbst wenn ein Agent `shape git diff` schriebe, greift der Wrapper-Kern:

- **Strikte Allowlist statt Denylist.** Der Wrapper kennt eine **kompilierte, geschlossene** Liste von Klasse-A-Befehlsköpfen (`ls`, `tree`, `find`, `grep`, `rg`, `git status`, `git log`, `docker ps`, `docker images`, `kubectl get`, `npm ls`, `pip list` — abgeleitet aus der AC1a-Tabelle des Eltern-Specs). Es gibt **keinen** `--all`/`--force`/„alle Befehle"-Modus. Diese Inversion ist der Kern: eine **Allowlist fail-open't in Sicherheit** (Unbekanntes → roh durchreichen), eine Denylist fail-open't in **Gefahr** (jeder neue, noch nicht gelistete Gate-Befehl würde gefiltert). Das ist die exakte Umkehrung von RTKs Fehler.
- **git-Subcommand-Prüfung.** Für `git` sind **nur** `status` und `log` Klasse A. Der Wrapper prüft das **zweite** Token; `git diff`, `git show`, `git blame` etc. sind nicht auf der Liste → roh durchgereicht. Der Befehlskopf `git` allein genügt nie.
- **Kein Shell, keine Verkettung.** Der Wrapper führt den gewrappten Befehl **direkt** aus (argv-Array, kein `sh -c`). Damit sind Verkettung/Pipes/Subshells (`&&`, `||`, `;`, `|`, `` ` ``, `$( )`) **konstruktiv unmöglich** — ein `shape 'ls && git diff'` kann keinen Klasse-B-Sub-Befehl ausführen; enthält das argv Shell-Metazeichen, verweigert der Wrapper die Interpretation und reicht roh durch.
- **Kein programm-startendes Argument bei sonst gelisteten Befehlen (Implementierungs-Auflage für die Umsetzungs-Story).** Manche Allowlist-Befehle können ohne Shell-Metazeichen fremden Programm-Output erzeugen — insbesondere `find … -exec <prog> {} +` / `-execdir` (und analog `-ok`/`-okdir`). Ein solcher Aufruf würde beliebigen (potenziell Gate-relevanten) Fremd-Output durch den Klasse-A-Transform schleusen, ohne dass Barriere 2 anschlägt. Der Wrapper MUSS argv auf solche programm-startenden Flags prüfen und bei Fund **roh durchreichen** (fail-open). Konkret zu sperrende Flags mindestens: `find`/`-exec`, `-execdir`, `-ok`, `-okdir`. (Als Auflage fürs Umsetzungs-Ticket vorgemerkt.)
- **Fail-open bei allem Unbekannten.** Jeder nicht eindeutig als Klasse A erkannte Befehl, jeder Parse-Zweifel, jeder interne Fehler → **Rohausgabe** + unveränderter Exit-Code des Kindprozesses (nie leer, nie abgeschnitten — E1-Prinzip des Eltern-Specs).

**Guarantee-Statement (prüfbar, Review-Kriterium):** Für jeden Befehl, der **strukturell** (per Befehlskopf/Subcommand) als Klasse B/C erkennbar ist, gilt: entweder er wird bare ausgeführt (Barriere 1 → Filter nicht im Pfad) **oder** er wird versehentlich gewrappt und von Barriere 2 byte-identisch roh durchgereicht. In **keinem** Pfad wird ein so erkennbares Klasse-B/C-Byte transformiert. Dieser Satz ist der Prüfstein für §6 (Fidelity-Test) und für das spätere Code-Review.

### 3.1 Residual-Risiko: intentions-abhängige Grenzfälle (`git log`, E2)

Ehrliche Grenze des strukturellen Ansatzes: **beide** Barrieren klassifizieren anhand des **Befehls** (Kopf + Subcommand), nicht anhand der **Absicht des Agenten mit der Ausgabe**. Ein Befehl, dessen Klasse von der Nach-Verwendung abhängt, kann daher strukturell nicht abgedeckt werden. Der Eltern-Spec dokumentiert genau einen solchen Fall (`docs/specs/output-token-shaping.md`, E2):

> `git log` ist Klasse A für die Übersicht — **aber** wird eine einzelne Commit-Message daraus **wörtlich als Beleg zitiert** (`coder/R02`/`reviewer/R01`), gilt für **genau diesen Aufruf** Klasse C.

Diese pro-Aufruf-Intention erkennt weder Barriere 1 (der Agent hat `shape` bewusst gesetzt) noch Barriere 2 (`git log` steht als Klasse A auf der Allowlist). Hier bleibt der Schutz **Konvention**, nicht Struktur — das wird hier offen benannt statt kaschiert.

**Warum trotzdem Variante (b) — Regel statt Degradierung, nicht (a):** `git log` aus der Allowlist zu nehmen würde den einzigen realen Nutzen (langes Historien-Log überfliegen → Dedup/Truncation) für **alle** Aufrufe opfern, um den seltenen Zitat-Fall zu adressieren — schlechtes Kosten/Nutzen-Verhältnis, zumal der Zitat-Fall ohnehin einen bewussten Belegakt darstellt, für den der Agent den Rohtext braucht. Stattdessen eine **bindende Handoff-Regel** (Prompt-Ebene, Teil der Adoptions-Story):

> **Regel `shape/G1`:** `shape git log` **nie** verwenden, wenn danach eine einzelne Commit-Message wörtlich als Klassifikations-Beleg zitiert werden soll — dafür **bare** `git log` fahren. `shape` ist für das Historien-Überfliegen, nie für die Beleg-Gewinnung. (Analog gilt: `git log` ist der **einzige** Allowlist-Eintrag mit intentions-abhängiger Grenze; `git show`/`git diff` sind bereits strukturell Klasse C/B und nie auf der Allowlist.)

Dieselbe Zitat-für-Beleg-Situation ist zusätzlich durch `coder/R02`/`reviewer/R01` gedeckt (Verbatim-Pflicht bei Klassifikations-Widerlegung) — d. h. der Agent ist ohnehin schon zur Rohtext-Nutzung verpflichtet, wenn er zitiert. Regel `shape/G1` macht diese bestehende Pflicht für den Wrapper-Kontext nur explizit; sie schafft keine neue Vertrauensbasis.

---

## 4. AC3 — Nur konservative, generische Tricks

Erlaubt sind **ausschließlich** zwei deterministische, struktur-agnostische, reihenfolge-erhaltende Transforms auf **stdout** (stderr wird immer roh durchgereicht — es trägt oft das eigentliche Signal):

1. **Dedup identischer aufeinanderfolgender Zeilen mit Count.** N identische Zeilen → **eine** Zeile + sichtbare Annotation ` (×N)`. Es wird **nie** eine Zeile ohne Count-Ausweis entfernt; die Summe aller Counts entspricht der Original-Zeilenzahl. Nicht-benachbarte Duplikate bleiben unberührt (keine globale Sortierung/Umordnung).
2. **Truncation mit Kontext UND explizitem Marker.** Überschreitet die Ausgabe eine Schwelle (z. B. > 200 Zeilen), werden Kopf **und** Fuß behalten und dazwischen ein sichtbarer Marker `[… M Zeilen ausgelassen (gesamt N) …]` eingefügt. Der Marker nennt die ausgelassene Zeilenzahl, damit der Agent weiß, dass etwas elidiert wurde, und bei Bedarf bare neu ausführen kann.

**Hart verboten** (das ist die operationalisierte RTK-Lehre): jede „smarte"/toolchain-spezifische Heuristik, Tail-Heuristiken („letzte 5 Zeilen"), kommentarloses Abschneiden, Kommentar-/Docstring-Strippen, Reflow, Umsortierung, jede Änderung am Byte-Inhalt einer **behaltenen** Zeile. Eine behaltene Zeile wird byte-für-byte emittiert. RTK starb an einer „smarten" Per-Tool-Heuristik — Weg A ist bewusst **generisch und dumm**.

---

## 5. AC4 — Anbindung an die Pack-`Output-Contract`-Schemata

**Entscheidung: die Kopplung ist per Default NULL — der Wrapper liest die Output-Contract-Tabellen NICHT.** Und das ist bewusst und AC2-konform.

Der `## Output-Contract`-Abschnitt (Eltern-ADR §6, `knowledge/<lang>.md`) beschreibt **Klasse-B**-Signal-vs-Rauschen-Regeln pro Toolchain (`pytest`-Traceback behalten, grüne Zeilen kürzen …). Würde der Wrapper diese Regeln lesen, hieße das per Definition, dass er auf **Klasse-B-Ausgabe** angesetzt wird — und genau das reintroduziert das RTK-Risiko, das §1–§3 strukturell ausschließen. Deshalb:

- Der Wrapper ist **generisch** (Dedup/Truncation, §4) und **command-agnostisch** — er braucht kein Per-Lang-Wissen und konsultiert die Packs nie.
- Der Output-Contract dient einem **anderen** Konsumenten: den **Agenten selbst** auf der Prompt-Ebene (Weg C), die beim Kuratieren von Test-/Diff-Ausgabe ins Handoff die Signal-Regeln **per Urteil** anwenden — nie mechanisch. Wrapper (mechanisch, Klasse A) und Output-Contract (Urteil, Klasse B) sind zwei **nicht-überlappende** Werkzeuge; ihre Trennung **ist** die strukturelle Brandmauer.
- **Konditional für eine ferne Zukunft:** wollte man je ein mechanisches Werkzeug für Klasse B bauen, das den Output-Contract liest, wäre das eine **neue, eigenständige Entscheidung** mit eigenem Fidelity-Gate — und **weiterhin kein prozessweiter Hook**. Für diese Story und ihre Umsetzung gilt: Klasse B bleibt außen vor, der Wrapper liest den Output-Contract nicht.

---

## 6. AC5 — Fidelity-Testplan (Gate vor jeder Aktivierung)

Ein reproduzierbarer, deterministischer Test, der **vor** jeder Aktivierung beweist, dass Gate-Ausgaben unverändert durchlaufen — analog zur Pilot-Gegenprobe S-345 (Gate-Ergebnisse Baseline vs. gefiltert müssen identisch sein). **Kein Rollout ohne bestandenen Test.** Selbst-enthalten (Fixtures im Repo), damit er in `agent-flow` (`language: md`, kein echter Toolchain) läuft; für Klasse-B/C-Fidelity genügen repräsentative, eingecheckte Roh-Ausgaben + ein winziges Fixture-Git-Repo (kein Netzwerk, kein realer Test-Runner nötig).

**Suite 1 — Pass-Through-Fidelity (HARTES Gate, Null-Toleranz).** Für einen Korpus aus Klasse-B/C-Befehlen — `git diff` (Fixture-Repo), `git show`, ein `pytest`/`cargo test`/`jest`-Fail-Log (als Fixture), `eslint`/`ruff`-Verstoß-Ausgabe, ein `curl`-Verbatim-Zitat — wird jeweils (a) bare und (b) via `shape <cmd>` ausgeführt und **Byte-Identität von stdout + identischer Exit-Code** asserted. Da Barriere 2 diese roh durchreicht, MUSS die Ausgabe byte-identisch sein. **Ein einziges abweichendes Byte = Test rot = kein Rollout.** Zusatzfälle: (i) `shape 'ls && git diff'` muss byte-identisch zu bare sein (Fail-open bei Metazeichen); (ii) `shape find . -exec cat {} +` muss byte-identisch zu bare sein (Fail-open bei programm-startenden Flags, §3 Barriere 2). Das beweist das Guarantee-Statement aus §3 sogar unter der falschen Annahme, ein Agent hätte Klasse B gewrappt. **Nicht durch Suite 1 abgedeckt** (weil intentions-abhängig, s. §3.1): der `git log`-Zitat-Grenzfall — dieser bleibt durch Regel `shape/G1` + `coder/R02`/`reviewer/R01` konventionell gesichert, nicht mechanisch testbar.

**Suite 2 — Transform-Korrektheit (Klasse A).** Für Klasse-A-Fixtures mit bekannter Ausgabe wird asserted: (a) jede **behaltene** Zeile ist byte-identisch zur Quellzeile; (b) die Dedup-Counts sind exakt (Summe = Original-Zeilenzahl); (c) der Truncation-Marker nennt die korrekte ausgelassene Zeilenzahl; (d) Exit-Code erhalten; (e) **keine** Zeile wird ohne Count/Marker verrechnet fallengelassen. Das operationalisiert AC3 (kein stiller Drop).

**Suite 3 — Fail-open/Robustheit (E1-Analog).** Malformte, binäre, sehr große Ausgabe → der Wrapper emittiert **nie** leere oder marker-los-abgeschnittene Ausgabe; bei jedem internen Fehler Fallback auf Roh-Pass-Through + unveränderter Exit-Code.

**Gate-Regel (bindend):** Suite 1 ist ein harter Blocker mit Null-Toleranz. Der Test wird als reproduzierbarer Check verdrahtet, der **grün sein muss, bevor** `shape` in irgendeinem Agenten-Handoff referenziert (= aktiviert) wird. Reihenfolge in der Umsetzungs-Story: (1) Wrapper + Tests bauen, (2) Suite 1 grün, (3) **erst dann** opt-in-Referenzen in `agents/*.md`. Regressionen an Suite 1 blockieren jede weitere Aktivierung.

---

## 7. Zusammenfassung der Entscheidungen

| AC | Entscheidung |
|---|---|
| **AC1** | **Wrapper-Befehl** (`shape`, opt-in, explizit) statt prozessweitem PreToolUse-Hook. Grund: strukturelle statt verhaltensbasierte Klasse-B/C-Garantie; minimaler Fehler-Radius; fail-safe-Adoption; auditierbar im Transkript. |
| **AC2** | Zwei unabhängige Barrieren: (1) Invocation-Boundary (Filter nicht im Pfad bare Befehle), (2) geschlossene **Allowlist** + git-Subcommand-Check + kein-Shell-Exec + fail-open. Kein `--all`-Modus. |
| **AC3** | Nur Dedup-mit-Count und Truncation-mit-Marker, reihenfolge-erhaltend, byte-treu für behaltene Zeilen. Keine „smarte"/Tail-Heuristik, kein kommentarloses Abschneiden. stderr immer roh. |
| **AC4** | Wrapper liest den Output-Contract **nicht** (Kopplung = NULL by design). Output-Contract dient der Prompt-Ebene (Agenten-Urteil, Klasse B), nicht dem Wrapper. Klasse B bleibt außen vor. |
| **AC5** | Dreiteiliger, selbst-enthaltener Fidelity-Test; Suite 1 (Byte-Identität für Klasse B/C) ist ein harter Null-Toleranz-Blocker vor jeder Aktivierung. |

**Kernempfehlung:** Klasse-A-Token-Nutzen über einen **expliziten, opt-in Wrapper-Befehl** mit interner Allowlist einfangen — nicht über einen prozessweiten Hook. Damit ist die Klasse-B/C-Unversehrtheit eine **Eigenschaft der Architektur** (der Filter ist gar nicht erst im Pfad der Gate-Befehle) statt eine Eigenschaft des Filter-Verhaltens — die strukturelle Antwort auf die RTK-Lehre.
