# Glossar — agent-flow (Ubiquitous Language)

> Begriffe der Fabrik einheitlich und sprach-neutral definiert — eine Quelle für die in `CONCEPT.md`, `AGENTS.md` und den Subsystem-Docs (`docs/architecture/*`) verwendeten Begriffe. Dogfooding von §4d: die Fabrik scaffoldet `glossary.md` für jedes Projekt und führt nun selbst eines.

## Fabrik & Betrieb

| Begriff | Bedeutung |
|---|---|
| **Fabrik** | `agent-flow` selbst: die wiederverwendbare, selbst-verbessernde Software-Fabrik als Claude-Code-Plugin. Bedient Projekt-Repos als Geschwister, ist nicht deren Parent. |
| **Orchestrator** | Die interaktive Haupt-Session (= das `/flow`-Skill). Einziger Schreiber von Board-Status und git/PR-Abschluss. |
| **Flow** | Ein Fabrik-Lauf über ein Board-Item: `coder → reviewer ⇄ Loop → tester → cicd`. Ausgelöst via `/flow`. |
| **Kern-Loop** | `coder → reviewer`, bei `CHANGES-REQUIRED` zurück an coder, bis `PASS`. Schleifenschutz: derselbe Befund überlebt max. 3 Iterationen, dann Blocked. |
| **Board** | GitHub Project v2 pro Projekt; zugleich Arbeits-Queue UND persistenter Zustand. Spalten: To Do │ In Progress │ Blocked │ In Review │ Done. |
| **Board-Item** | Eine Arbeitseinheit (≈ ein coder→reviewer→tester-Lauf). Trägt Titel, Spec-Referenz + AC-Nummern, Priority/Order, optional Depends-on, Status. |
| **Handoff / Handoff-Marker** | Definierte Übergabe zwischen Agenten (z. B. `Review-Handoff: REVIEW REQUIRED`, `Review-Gate: PASS`, `Test-Gate: PASS`). |
| **Cost-Mode** | `low-cost | balanced | max-quality`. Steuert pro Lauf, mit welchem Modell jeder Agent dispatcht wird. `balanced` = Default (Agent-Frontmatter gilt). Auflösung: `--cost` > `profile.cost_mode` > `balanced`. |
| **SHIP-TRIGGER** | Auftrag des Orchestrators an `cicd`, nach tester-PASS die Abschluss-Sequenz (landen + CI-Watch + Rollout + Prune) auszuführen. |

## Agenten (Rollen)

| Begriff | Bedeutung |
|---|---|
| **Agent / Rolle** | Generischer, sprach-neutraler Akteur. Sprach-/Domänen-Expertise kommt zur Laufzeit aus den Knowledge Packs (Rolle ≠ Expertise). |
| **requirement** | Front-of-Funnel: verfeinert eine vage Anforderung in durable Specs + referenzierende Board-Items. Schreibt keinen Code. |
| **architekt** | Definiert die App-Architektur → bindende `docs/architecture.md` (ADR-Stil). Kein Code. |
| **dba** | Erarbeitet das Datenmodell → bindende `docs/data-model.md`. Schreibt keine Migrationen/SQL (das macht der coder via sql-Pack). |
| **designer** | Definiert Design-System + UX/A11y → bindende `docs/design.md`. Kein Code; Design-Review macht der reviewer. |
| **coder** | Implementiert ein Board-Item gegen die Spec (AC); self-test; Handoff an reviewer. |
| **reviewer** | Prüft den Diff gegen Spec + Konventionen; kategorisiert Critical/Important/Suggestions; setzt das Review-Gate; härtet das Drift-Gate. Kein Produktivcode. |
| **tester** | Formelles Gate nach Review-PASS: Build + Tests + Smoke + Coverage-Gate gegen die Spec-AC. Kein Code. |
| **cicd** | Abschluss-Arm ab tester-PASS: git-Landen, CI-Watch, lokaler Docker-Rollout (rm+run, nie restart), Disk-Hygiene (`docker image prune -f`). |
| **retro** | Meta-Agent: destilliert wiederkehrende Tier-1-Lessons in Pack-/Skill-Verbesserungen. Liefert als PR. |
| **train** | Meta-Agent: recherchiert aktuelle Patterns je Sprache aus autoritativen Quellen → Pack-Update als PR (max. 3 Regeln/Lauf). |
| **teamLeader** | Meta-Agent (später): gliedert einen neuen Agenten ins Team + den Workflow ein, via PR+Gate. |
| **Meta-Agent** | Agent, der die Fabrik selbst verbessert (retro, train, teamLeader) — nicht den App-Code. |

## Spezifikation & Traceability

| Begriff | Bedeutung |
|---|---|
| **Spec / Spezifikation** | `docs/specs/<feature>.md`: durable, sprach-neutrale Beschreibung mit testbaren Acceptance-Kriterien. Source of Truth, dem Code vorgelagert (§4d). |
| **Detailkonzept** | `architecture.md` / `data-model.md` / `design.md`: logische, nicht sprachliche Ebene zwischen Konzept und Spec. |
| **AC (Acceptance-Kriterium)** | Nummeriertes, testbares Kriterium (`AC1`…) mit stabiler ID in einer Spec; der Pflicht-Vertrag (Use-Case-2.0-Hybrid). |
| **BR-NNN (Geschäftsregel)** | Business Rule, zentral in `architecture.md` (Verhalten) bzw. `data-model.md` (Validierung + Enforcement-Layer). Specs referenzieren via `(→ BR-NNN)`, Tests taggen `#BR-NNN`. |
| **Trace-Token / @trace** | Kanonisches Tag im Testcode: `@trace <spec-slug>#AC<n>[,BR-NNN]`. Verknüpft Test ↔ Spec. Map wird abgeleitet, nie handgepflegt. |
| **Glossar / Ubiquitous Language** | Diese Datei: einheitliche Domänenbegriffe über Konzept, Spec und Code — stützt Portabilität und verhindert Begriffs-Drift. |

## Gates

| Begriff | Bedeutung |
|---|---|
| **Review-Gate** | reviewer-Verdikt: `PASS | CHANGES-REQUIRED`. PASS nur wenn Critical UND Important leer. |
| **Drift-Gate** | Hartes reviewer-Gate: ein Diff, der beobachtbares Verhalten ohne Spec-Delta ändert → `CHANGES-REQUIRED`. Code + Spec landen im selben PR. |
| **Test-Gate** | tester-Verdikt: `PASS | FAIL`. PASS nur bei grünem Build + grünen Tests + allen genannten AC + grünem Coverage-Gate. |
| **Coverage-Gate** | tester prüft: jede genannte AC + jede referenzierte BR von ≥ 1 Test gedeckt (über Trace-Tags). Lücke = `TRACE-GAP` → FAIL. |
| **Rollout-Gate** | cicd-Verdikt nach dem produktiven Rollout: `PASS | FAIL | NEEDS-HUMAN`. |
| **Gate (§5)** | Self-Improvement-Sicherung: Pack-/Skill-Änderungen laufen nie direkt auf `main` → PR → reviewer-Check + Mensch-Approve → merge. |

## Wissen & Self-Improvement

| Begriff | Bedeutung |
|---|---|
| **Knowledge Pack** | Versionierte Sprach-/Domänen-Wissensdatei `knowledge/<x>.md` (Abschnitte: Coder-Guidance, Reviewer-Checklist, Test-Approach, Spec-Tagging). Neue Sprache = neue Datei, kein neuer Agent. |
| **Harness** | Die ausführbare Architektur-Schicht zwischen Spec und Code: Knowledge Packs + Skills + Guidelines. (AIUP-Begriff; in der Fabrik via Packs/Skills realisiert.) |
| **Security-Floor (⛑)** | Sicherheits-Mindestregeln in `knowledge/security.md`, die coder/reviewer IMMER anwenden — auch ohne `domains:[security]`. |
| **Regel-ID (`lang/R<NN>`)** | Stabile ID einer Pack-Qualitätsregel (z. B. `java/R07`). Vom reviewer beim Befund getaggt — macht Self-Improvement messbar. Namensraum getrennt von `BR-NNN`. |
| **Tier-1-Lessons** | Projekt-lokale gelernte Regeln in `.claude/lessons/{coder,reviewer,tester}.md`. reviewer schreibt, coder liest. |
| **LEARNINGS.md** | Globaler Self-Improvement-Ledger der Fabrik; eine Zeile pro Promotion (ID, Datum, Pack, Regel, Quelle, PR, Status). |
| **Improvement-Board** | Eigenes GitHub Project der Fabrik (Dogfooding): jede retro/train-Promotion als Karte (Proposed → Merged → Measuring → Validated | Reverted). |
| **Self-Improvement** | Verbesserung der Fabrik durch retro/train — stets via PR + Gate, nie Direkt-Edit der Live-Skills. |

## Projekt-Bootstrap & Zustand

| Begriff | Bedeutung |
|---|---|
| **Profile (`.claude/profile.md`)** | Projekt-Sprach-/Build-Profil: Sprache, Build/Test/Lint/Smoke, `merge_policy`, `cost_mode`, Board-Ref, Deploy-Ziel. |
| **new-project / init / adopt** | Bootstrap-Skills: `new-project` legt ein neues Repo an, `init` adoptiert ein bestehendes (inkl. „Spec aus Code“), `adopt` forkt + auditiert ein fremdes Repo. |
| **Preview / `/preview`** | Ephemerer, wegwerfbarer Dev-/PR-Container (Mac: `localhost`, VPS: `<app>.alexstuder.cloud`). Source of Truth bleibt das ghcr-Image. |
| **merge_policy** | `pr | direct`: ob Code pro Item als PR (Default) oder direkt auf `main` landet. |

## Links

- Vollständiges Konzept: `CONCEPT.md`
- Agenten-Specs: `AGENTS.md`
- Subsysteme: `docs/architecture/*`
