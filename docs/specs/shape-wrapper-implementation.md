---
id: shape-wrapper-implementation
title: shape-Wrapper — Umsetzung + Adoption (Weg A)
status: active
area: rollen-agenten
version: 1
spec_format: use-case-2.0
---

# Spec: shape-Wrapper — Umsetzung + Adoption  (`shape-wrapper-implementation`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**.
> **Source of Truth** für `coder` (baut), `tester` (führt die Fidelity-Suiten aus + Gate), `reviewer` (prüft gegen das Design — hartes Drift-Gate).
> **Bindender Bauplan:** [`docs/architecture/output-shaping-classA-filter.md`](../architecture/output-shaping-classA-filter.md) (Design-Entscheidung S-067). Diese Spec setzt ihn 1:1 um — keine Design-Abweichung ohne Spec-Update.

## Zweck
Weg A aus dem ADR umsetzen: den Klasse-A-Token-Nutzen (~65–80 %) mechanisch einfangen über einen **opt-in Wrapper-Befehl `scripts/shape`** — mit der strukturellen Garantie, dass Klasse-B/C-Ausgabe (Gate-/Verbatim-Quellen) **nie** transformiert wird. Reihenfolge laut Design §6: (1) Wrapper + Tests bauen, (2) Suite 1 grün, (3) **erst dann** Adoption in `agents/*.md`.

## Acceptance-Kriterien

- **AC1 — Wrapper `scripts/shape` (Barrieren).** `scripts/shape` existiert, ausführbar (`chmod +x`), POSIX-/bash-Shell. Verhalten:
  - Führt den gewrappten Befehl **direkt** aus (argv-Array, **kein** `sh -c`), Exit-Code des Kindprozesses unverändert durchgereicht.
  - **Geschlossene Allowlist** der Klasse-A-Befehlsköpfe: `ls`, `tree`, `find`, `grep`, `rg`, `git status`, `git log`, `docker ps`, `docker images`, `kubectl get`, `npm ls`, `pip list`. Kein `--all`/„alle Befehle"-Modus.
  - **git-Subcommand-Check:** bei `git` sind **nur** `status` und `log` Klasse A (zweites Token geprüft); `git diff`/`show`/`blame`/… → roh durchgereicht.
  - **Fail-open (roh + Original-Exit) bei:** unbekanntem Befehlskopf; Shell-Metazeichen im argv (`&&`, `||`, `;`, `|`, `` ` ``, `$(`, `>`, `<`, `&`); programm-startenden `find`-Flags (`-exec`, `-execdir`, `-ok`, `-okdir`); jedem internen Fehler/Parse-Zweifel. **Nie** leere oder marker-los abgeschnittene Ausgabe.
- **AC2 — Konservative Transforms (nur Klasse A, nur stdout).** Auf stdout eines allowlisteten Befehls **ausschließlich**: (a) **Dedup** identischer **aufeinanderfolgender** Zeilen → eine Zeile + sichtbare Annotation ` (×N)`; Summe aller Counts = Original-Zeilenzahl; nicht-benachbarte Duplikate unberührt (keine Umsortierung). (b) **Truncation** bei > 200 Zeilen: Kopf **und** Fuß behalten, dazwischen Marker `[… M Zeilen ausgelassen (gesamt N) …]`. Die 200-Zeilen-Schwelle bezieht sich auf die Zeilenzahl **nach** Schritt (a) (dedupliziert) — Transforms wirken sequenziell (erst Dedup, dann Truncation auf das Ergebnis). **Jede behaltene Zeile byte-identisch** zur Quelle. **stderr immer roh.** Keine weiteren Transforms (keine Tail-Heuristik, kein kommentarloses Abschneiden, kein Strippen/Reflow/Umsortieren).
- **AC3 — Fidelity Suite 1 (HARTES Gate, Null-Toleranz).** Automatisierter, selbst-enthaltener Test (`tests/shape/`, eingecheckte Fixtures, kein Netz/kein realer Toolchain) beweist Byte-Identität stdout + gleicher Exit-Code für `shape <cmd>` vs. bare bei: `git diff` (Fixture-Repo), `git show`, ein Test-Fail-Log-Fixture (jest/pytest-Stil), eine Lint-Verstoß-Ausgabe (Fixture), ein `curl`-Verbatim-Zitat (Fixture); **plus** (i) `shape 'ls && git diff'` byte-identisch zu bare, (ii) `shape find . -exec cat {} +` byte-identisch zu bare. **Ein abweichendes Byte = rot = kein Rollout.**
- **AC4 — Fidelity Suite 2 + 3 (grün).** Suite 2 (Transform-Korrektheit Klasse A): behaltene Zeilen byte-identisch, Dedup-Counts exakt (Summe = Original), Truncation-Marker nennt korrekte ausgelassene Zeilenzahl, Exit-Code erhalten, keine Zeile ohne Count/Marker fallengelassen. Suite 3 (Fail-open/Robustheit): malformte/binäre/sehr große Ausgabe → nie leer/marker-los-abgeschnitten, Fallback auf Roh-Pass-Through. Alle Suiten laufen über `tests/shape/run-test.sh` (Exit 0 = grün).
- **AC5 — Adoption in `agents/*.md` (erst NACH Suite 1 grün).** `agents/coder.md`, `agents/reviewer.md`, `agents/tester.md` referenzieren `shape <cmd>` **opt-in** für die Klasse-A-Explorationsbefehle (mind. `ls`, `find`, `grep`/`rg`, `git status`, `git log`, `tree`) — als Empfehlung, wo die Ausgabe reine Orientierung ist. **Bindende Regel `shape/G1` im Text:** `shape git log` **nie** verwenden, wenn danach eine Commit-Message wörtlich als Beleg zitiert wird — dafür bare `git log`. Verbatim-/Fidelity-Doktrin (`coder/R02`, `reviewer/R01`) bleibt **byte-unverändert**.
- **AC6 — Nicht-Ziele strukturell eingehalten (im Diff nachweisbar).** Kein PreToolUse-Hook (prozessweit) wird installiert; der Wrapper liest **keine** `knowledge/<lang>.md` Output-Contract-Tabelle (Kopplung NULL); kein `--all`-Modus. `git diff`/Test-/Build-Output/Verbatim-Quellen sind strukturell nie im Transform-Pfad.

## Verträge
- **Ort:** `scripts/shape` (Fabrik-Tooling, analog `scripts/metrics-*.sh`). Tests unter `tests/shape/`.
- **Fail-open ist der Default für jeden Zweifel** — Fidelity vor Ersparnis, ausnahmslos.
- **Aktivierungs-Gate:** AC5 (Adoption) darf erst gelandet werden, wenn AC3 (Suite 1) grün ist — Reihenfolge ist bindend.

## Edge-Cases & Fehlerverhalten
- **E1 — malformte/binäre Ausgabe:** roh durchreichen, nie transformieren (Suite 3).
- **E2 — `git log`-Zitat-Grenzfall:** intentions-abhängig, nicht mechanisch testbar → Regel `shape/G1` + Verbatim-Doktrin (Design §3.1).
- **E3 — Befehl schlägt fehl (Exit ≠ 0):** Exit-Code unverändert durchreichen; stdout-Transform nur wenn allowlistet, sonst roh.

## NFRs
- Kein Secret in Skript/Logs. Keine neuen Laufzeit-Dependencies (reines bash + coreutils).
- Deterministisch, kein Netzwerk, kein LLM-Aufruf zur Ausführung.

## Nicht-Ziele
- Kein Hook, kein Klasse-B-Transform, keine Output-Contract-Kopplung (Design §4/§5).
- Keine Änderung an `coder/R02`/`reviewer/R01` oder der A/B/C-Trennlinie.
- Keine Verteilung ins Konsum-Scaffold in dieser Story (agent-flow-lokal; Scaffold-Verteilung wäre eine eigene Story).

## Abhängigkeiten
- [`docs/architecture/output-shaping-classA-filter.md`](../architecture/output-shaping-classA-filter.md) (Bauplan), [`docs/specs/output-token-shaping.md`](output-token-shaping.md) (A/B/C-Trennlinie), [`output-shaping-prompt-frugality`](output-shaping-prompt-frugality.md) (Weg C, Grundhaltung).
