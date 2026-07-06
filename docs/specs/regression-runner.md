---
id: regression-runner
title: Regressions-Runner — deterministische Ausführung, Testobjekt/target, Infra-Leitplanken
status: active
version: 1
spec_format: use-case-2.0
area: auslieferung
---

# Spec: Regressions-Runner  (`regression-runner`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge** der deterministischen Regressions-Ausführung.
> **Source of Truth** für `coder` (baut Runner-Skript + Vorbedingungs-Check + Leitplanken), `reviewer` (Drift-Gate + Security-Floor), `tester` (prüft die AC).
>
> **Detailkonzept-Bindung.** Diese Spec definiert die **deterministische Ausführung** (kein Agent pro Testlauf), das **Testobjekt/`target`**-Modell (`local | ephemeral-infra | url`) und die **Infra-Leitplanken** (`rtest-*`-Namensschema, Produktiv-Allowlist, garantiertes Cleanup). Sie hängt an der Auslieferung: `target: local` läuft gegen den von `cicd` zuletzt lokal ausgerollten Container.

## Zweck

Regressions-Läufe laufen **ohne Agent**, reproduzierbar und sicher. Jede Suite deklariert ihr **Ziel** explizit; Bereichs-Suiten prüfen per Default die lokal ausgerollte Applikation, Infra-Suiten erzeugen/zerstören ihr eigenes Wegwerf-Ziel. Test-Ressourcen sind strikt vom Produktivbestand getrennt und werden **immer** aufgeräumt — auch im Fehlerpfad.

## Kontext / Designnuancen (bindend)

- **Deterministisch, kein Agent pro Testlauf** — Agenten kommen nur beim Definieren/Heilen ([[regression-define]]/[[regression-heal]]) zum Einsatz.
- **Testobjekt-Klärung (Owner, 2026-07-03, bindend):** jede Suite deklariert `target: local | ephemeral-infra | url` im Kopf der Begleitbeschreibung.
- **Default Bereichs-Suiten (UI/API) = `local`** = die lokal auf Docker laufende Applikation (`http://localhost:<port>`, der von `cicd` zuletzt ausgerollte Stand; Port aus Projekt-Profil/Compose).
- **Infra-/Verbund-Suiten = `ephemeral-infra`** — erzeugen/zerstören ihr eigenes Wegwerf-Ziel (`rtest-*`).
- **`target: url`** (z.B. Preview-Instanz) ist optional wählbar.

## Main Success Scenario

1. Der Runner liest die Begleitbeschreibung der Suite und ermittelt `target`.
2. Bei `target: local` prüft er die **Erreichbarkeit** des lokal ausgerollten Containers (`http://localhost:<port>`, Port aus Profil/Compose).
3. Er führt die Playwright-Suite deterministisch aus (kein Agent) und schreibt CTRF+JUnit-Reports.
4. Bei `ephemeral-infra` provisioniert er das Wegwerf-Ziel (`rtest-*`), läuft dagegen und baut es garantiert wieder ab.
5. Ergebnis + Artefakte liegen in `test-results/`/`playwright-report/` (gitignored).

## Alternative Flows

### E1: local-Ziel nicht erreichbar (Vorbedingungs-Fehler)
- Vor einem `local`-Lauf ist der Container nicht erreichbar → der Runner meldet einen **klaren Vorbedingungs-Fehler** (z.B. „Ziel-Container `http://localhost:<port>` nicht erreichbar — zuerst `cicd rollout`/Container starten") **statt** roter Testfälle.

### E2: Lauf schlägt fehl / bricht ab (ephemeral-infra)
- Ein `ephemeral-infra`-Lauf schlägt fehl oder bricht ab → das Cleanup baut die `rtest-*`-Ressourcen **trotzdem** ab (garantierter Teardown auch im Fehlerpfad).

## Acceptance-Kriterien

- **AC1** — Ausführung ist **deterministisch**: pro Testlauf wird **kein Agent** dispatcht (Agenten nur beim Definieren/Heilen).
- **AC2** — Jede Suite deklariert ihr Testobjekt im Kopf der Begleitbeschreibung: `target: local | ephemeral-infra | url`.
- **AC3** — Default für Bereichs-Suiten (UI/API) ist `local` = die lokal auf Docker laufende Applikation `http://localhost:<port>` (der von `cicd` zuletzt ausgerollte Stand; Port aus Projekt-Profil/Compose).
- **AC4** — Infra-/Verbund-Suiten tragen `target: ephemeral-infra` und **erzeugen + zerstören** ihr eigenes Wegwerf-Ziel; dessen Ressourcen tragen das `rtest-*`-Namensschema.
- **AC5** — `target: url` (z.B. Preview-Instanz) ist optional wählbar; der Runner läuft gegen die angegebene URL, ohne lokal zu provisionieren.
- **AC6** — Vor einem `local`-Lauf prüft der Runner die **Erreichbarkeit** des Containers; bei Nicht-Erreichbarkeit meldet er einen **klaren Vorbedingungs-Fehler** statt roter Testfälle (deckt E1).
- **AC7** — Infra-Leitplanke: Test-Ressourcen folgen ausnahmslos dem `rtest-*`-Namensschema; **produktive Ressourcen** sind per **Allowlist** unantastbar (der Runner operiert nie auf nicht-`rtest-*`/nicht-allowlisteten Ressourcen).
- **AC8** — Infra-Leitplanke: Cleanup/Teardown ist **garantiert** — auch bei Fehlschlag/Abbruch werden die `rtest-*`-Ressourcen abgebaut (deckt E2).
- **AC9** — Secrets werden zur **Laufzeit** aus dem Credential-Store injiziert (nie aus Test-/Datendateien gelesen); der Runner reicht sie an Playwright durch, ohne sie zu persistieren.

## Verträge

### Begleitbeschreibungs-Kopf (`<suite>.md`)
```
target: local            # local | ephemeral-infra | url
url: <nur bei target=url>
kosten: <nur bei ephemeral-infra: Kosten-/Ressourcen-Deklaration>
```

### Testobjekt-Auflösung
| `target` | Ziel | Herkunft |
|---|---|---|
| `local` (Default Bereich) | `http://localhost:<port>` | zuletzt via `cicd` ausgerollter Container; Port aus `profile`/Compose |
| `ephemeral-infra` | selbst-provisioniertes `rtest-*`-Ziel | Runner erzeugt + zerstört (Fixture-Teardown, [[regression-playwright-conventions]] AC4) |
| `url` | angegebene URL (z.B. Preview) | Begleitbeschreibung `url:` |

### Infra-Leitplanken (Constraint)
- Namensschema: alle Test-Ressourcen `rtest-*`.
- Produktiv-Allowlist: der Runner fasst ausschließlich `rtest-*`-Ressourcen an; alles andere ist tabu.
- Cleanup: garantiert (auch Fehler-/Abbruchpfad).

## Edge-Cases & Fehlerverhalten

- **`target` fehlt im Kopf** → Fehler „Begleitbeschreibung ohne `target`" (kein stillschweigender Default auf Produktiv-URL).
- **`local`-Port nicht in Profil/Compose auffindbar** → Vorbedingungs-Fehler (AC6-Klasse), nicht roter Lauf.
- **`rtest-*`-Ressource kollidiert mit Allowlist-Eintrag** → Abbruch mit Leitplanken-Fehler (AC7 hat Vorrang, keine Produktiv-Berührung).

## NFRs

- **Sicherheit (Security-Floor):** Produktivbestand unantastbar (Allowlist), keine Secrets in Artefakten, garantiertes Cleanup — security-relevant, unter Drift-Gate.
- **Reproduzierbarkeit:** deterministische Ausführung, keine Agent-Varianz pro Lauf.

## Nicht-Ziele

- Definition/Übersetzung von Tests ([[regression-define]]) und Heilung ([[regression-heal]]).
- Der Credential-Store selbst ([[secrets-subsystem]] / bestehende Secrets-Mechanik) — hier nur die Runtime-Injektion.
- Das Anlegen des Grundgerüsts ([[regression-scaffolding]]).

## Abhängigkeiten

- [[regression-playwright-conventions]] — Layout, Reporter, Fixture-/Teardown-Muster.
- `cicd` / [[new-project-board]]-Profil — liefert `image`/`container_port`/`preview_port` für die `local`-Ziel-Auflösung.
- Secrets-Mechanik der Fabrik (`docs/architecture/secrets-subsystem.md`) — Quelle der Runtime-injizierten Credentials.
