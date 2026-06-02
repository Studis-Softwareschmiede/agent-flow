---
name: upgrade
description: Autonomer Stack-Modernisierer — erkennt Ist-Versionen eines Projekts, recherchiert die neuesten, löst Cross-Achsen-Kompatibilität (Solver), schreibt einen UpgradePlan als Spec + Board-Leiter, schließt fehlende Knowledge-Packs via train --bootstrap und arbeitet die Leiter eingaben-frei via /flow ab (Test-Loop), gefolgt von retro. Im Ziel-Projekt-Repo ausführen. Bindende Spec: docs/architecture/upgrade-subsystem.md.
---

# /upgrade — autonomer Stack-Modernisierer (Orchestrator)

Du hebst ein bestehendes Projekt **eingaben-frei** auf den neuesten, kompatiblen, sichersten, funktionierenden Stand. Du bist Orchestrator wie `/flow` — du erzeugst den Plan und **delegierst die Ausführung an `/flow`**, erfindest keinen zweiten Build-Loop. cwd = Ziel-Projekt-Repo. **Bindende Spec: [`docs/architecture/upgrade-subsystem.md`](../../docs/architecture/upgrade-subsystem.md)** (Phasen A–F, Solver §6, hermetisches Loading §10, Autonomie §11) — bei Konflikt gilt die Spec.

> **Autonomie-Posten.** Dieser Lauf ist auf **Overnight ohne Zwischeneingriff** ausgelegt: keine `AskUserQuestion` im Normalpfad, kein Warten auf Merges. Entscheidungen trifft der Solver deterministisch; Unlösbares wird **Blocked** (nicht erfragt) und landet im Abschluss-Report. Läuft als **eine interaktive Abo-Session** (kein API/Cron — CONCEPT §9 bleibt gewahrt).

## 0. Setup
- `.claude/profile.md` lesen. **Vorbedingung:** Repo ist adoptiert (`profile` existiert, `adoption_validated_at != null`). Fehlt das → **STOPP** mit Hinweis „erst `/adopt` ausführen" (nichts raten).
- Arbeits-Repo **Fork-sicher** + `default_branch` auflösen + Auth — **identisch zu `/flow` §0** (`repo` über die origin-URL, `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"`).
- **Run-ID + hermetischer Staging-Dir** (Spec §10):
  - `run_id` = aktuelles ISO-Datum + Kurz-Slug (z.B. `2026-06-02-upgrade`). Liegt im `profile.upgrade`-Block bereits ein `run_id` mit `status: planning|executing` → **Resume**: der Staging-Dir besteht bereits — **`AGENT_FLOW_KNOWLEDGE_DIR` erneut exportieren** (s.u.), Phasen A–E überspringen, weiter bei §6. (Ein nacktes `/flow` ohne diesen Export degradiert auf den Plugin-Cache — Spec §11.)
  - Staging-Dir anlegen: `mkdir -p .claude/upgrade/<run_id>/knowledge` und die **aktiven Packs hineinkopieren** (`cp -R "$CLAUDE_PLUGIN_ROOT/knowledge/." .claude/upgrade/<run_id>/knowledge/`). `.claude/upgrade/` ist gitignored (ist es nicht → `.gitignore`-Zeile ergänzen, als Teil des Plan-Commits).
  - **`export AGENT_FLOW_KNOWLEDGE_DIR="$PWD/.claude/upgrade/<run_id>/knowledge"`** — gilt für den ganzen Lauf; alle dispatchten Agenten lesen Packs zuerst von dort (Loader-Override, `framework-build-subsystem.md` §5).

## 1. Detect (Phase A)
- Ist-Versionen je Achse aus `profile` **und** den Dependency-Koordinaten lesen (Heuristiken aus `/adopt`: `framework-build-subsystem.md` §6, `migration-tool-subsystem.md` §6): `language` (+ konkrete JDK/Node-Version aus `pom.xml`/`.nvmrc`/Toolchain-Block), `frameworks[]`, `build`, `db_dialect`, `db_migration_tool`, `container_runtime`.
- Ergebnis: `current[]` (Achse → Ist-Version). Im Lauf-Log festhalten.

## 2. Research (Phase B)
- Pro Achse die **neueste stabile + empfohlene** Version ermitteln, mit `train`-Quellen-Disziplin (nur `primary_sources`-artige autoritative Quellen; `non_sources` ignorieren; **Preview ≠ stable**; verbatim belegen). Sprache: neueste **LTS** (nicht zwingend neuestes Release).
- Ergebnis: `latest[]` (Achse → Kandidat + Quell-Link). Kandidaten gehen in den Solver, nicht ungeprüft ins Ziel.

## 3. Solve (Phase C) — Kompatibilitäts-Solver
Quelle: **Pack-Header-Constraints** (`requires`/`compatible_with`/`incompatible`, §3 framework-build-subsystem) zuerst; **Web-Fallback** für Ziele ohne Pack-Constraints (gefundene Constraints für Phase E vormerken).
1. Für jedes Kandidaten-Ziel `requires`/`incompatible` transitiv sammeln (Staging-Dir-Packs nutzen — Loader-Override).
2. **Konflikte** erkennen: Versions-Floor (z.B. Ziel-Framework und Ziel-Migrations-Tool fordern unterschiedliche Sprach-Minima) und Ausschlüsse (`incompatible: container=<x>` gegen `profile.container_runtime`).
3. **Auflösen statt abbrechen:** Floor-Konflikt → gemeinsames Maximum der Minima auf eine **unterstützte LTS/Major** anheben (Begründung + Quelle protokollieren). Ausschluss → Konflikt-Achse auf kompatible Alternative heben **nur innerhalb des Scope** (Runtime-Wechsel ok; Framework-/Tool-**Wechsel** nicht → diese Stufe als **Blocked** planen).
4. **Reihenfolge** topologisch nach `requires`: `language → build → frameworks (Leiter über Majors) → migration → db`.
- **Determinismus:** bei mehreren gültigen Auflösungen feste Präferenz — neueste LTS der Sprache > neueste GA des Frameworks > Minimal-Anhebung der übrigen Achsen (damit Resume dasselbe Ergebnis liefert).
- Ergebnis: `target[]` (konsistentes Ziel-Set) + `order[]` (Bump-Reihenfolge) + `conflicts[]` (unlösbar → werden Blocked-Stufen).

## 4. Plan (Phase D) — UpgradePlan-Spec + Board-Leiter
- **Spec schreiben** (durable, Drift-Gate): `docs/specs/upgrade-<run_id>.md` aus [`templates/_shared/upgrade-plan.md`](../../templates/_shared/upgrade-plan.md). Enthält Ist→Ziel-Tabelle je Achse, Solver-Begründung **mit Quell-Links**, und **eine nummerierte AC-Gruppe pro Leiter-Stufe** (z.B. `AC-A1: java auf 21 — Build grün`; `AC-F1: angular 13→14 — ng update + Tests grün`).
- **Board-Items als Leiter:** **ein Item pro Major-Stufe pro Achse**, in `order[]`, mit `Depends-on`-Kette (jede Stufe hängt an der vorigen + den Achsen-Vorbedingungen aus dem Solver). Item-Body: `Spec: docs/specs/upgrade-<run_id>.md` + `implements: AC-<…>` + `Priority` + `Depends-on`. Label `upgrade` (+ `db` wenn DB-Achse berührt → DBA-Review-Trigger in `/flow`).
- **Gap-Stufen** (Phase E nötig): bekommen ein **vorgelagertes Gap-Item** als `Depends-on`.
- **Plan-Commit:** Spec + `.gitignore`-Zeile + `profile.upgrade`-Block (`run_id`, `targets`, `status: planning`, `timeout_hours`) committen. **Das ist der initiale direkte git/Board-Eingriff von `/upgrade`** — die zwei weiteren erlaubten (Status-Folge-Commit §6, Profil-Rückschreib §7) sind im Abschnitt **Grenzen** abgegrenzt; alles Übrige ist `/flow`-Hoheit (Single-Writer-Erweiterung, Spec §3/§7).
- Board-Item-Anlage via `gh issue create` + `gh project item-add` (Mechanik wie `/requirement`/`/adopt`). **Plus ein Tracking-Item** „UpgradePlan <run_id>" (Label `upgrade`), an das §7 den Abschluss-Report hängt.

## 5. Gaps (Phase E) — fehlende Packs schließen
Für jedes Ziel ohne passenden Pack (`target[]` gegen Staging-Dir/Plugin-Cache prüfen):
- **`train --bootstrap <pack-id>`** dispatchen (Task). Der Agent legt das Pack an (Skelett aus Vorgänger bei Cut + Sektion A aus Primärquellen + Solver-Constraints), schreibt es in **`$AGENT_FLOW_KNOWLEDGE_DIR`** (sofort nutzbar) **und** öffnet einen PR gegen agent-flow (`bootstrap/<pack-id>`, Durability, Mensch-Gate). Vertrag: `agents/train.md` „Bootstrap-Modus".
- Den agent-flow-Bootstrap-PR **NICHT** mergen (Mensch-Gate, Spec §1). Im Report vermerken.
- **Echte neue Agenten-Rolle/Tool nötig** (keine Pack-Lücke, sondern fehlende Fähigkeit) → die betroffene Stufe **Blocked** + `teamLeader`-Vorschlag in den Report (kein autonomes Anlegen neuer Agenten — Spec §8).

## 6. Execute (Phase F) — via /flow, Test-Loop
- **`/flow` ausführen** (im selben cwd, mit gesetztem `AGENT_FLOW_KNOWLEDGE_DIR`): es arbeitet die Leiter-Items in `Depends-on`-Reihenfolge ab — unverändertes `coder → reviewer ⇄ Loop → tester → landen → Done`. Jede Stufe = `ng update`/Dependency-Bump + Schematics + Build/Tests grün als AC.
- **`profile.upgrade.status: executing`** setzen (Folge-Commit) vor dem ersten `/flow`-Item.
- **Failure-Isolation (Spec §11):** Eine Stufe, die der Schleifenschutz (max. 3) nicht durchbringt, oder eine Solver-`conflicts[]`-Stufe → bleibt **Blocked**; `/flow` arbeitet **unabhängige** Stufen weiter (`Depends-on`-Graph isoliert — nur Nachfahren der blockierten Stufe werden übersprungen). **Nie** Merge auf rotem Review/Test.
- **Gesamt-Timeout:** `profile.upgrade.timeout_hours` (falls gesetzt) als weiche Obergrenze beachten — bei Überschreitung sauber bei §7 abschließen (Rest bleibt als offene Items fürs nächste `/upgrade`).

## 7. Finalize — Profil, Retro, Report
1. **Profil zurückschreiben:** erreichte Ziel-Versionen (alle Stufen einer Achse `Done`) in die regulären Achsen-Felder (`frameworks`, `db_migration_tool`, `language`-Toolchain, `container_runtime`). DB-Achse berührt → `adoption_validated_at: null` (Re-Validate beim nächsten `/preview`/`/adopt`, analog `/flow` §5a). `profile.upgrade.status: done` (oder `blocked`, wenn offene Stufen).
2. **Retro:** `/retro` dispatchen — destilliert die Lauf-Lessons (`.claude/lessons/*`) in die Packs (PR+Gate, CONCEPT §5) → nächstes Upgrade effizienter. Greift der wöchentliche Retro-Cooldown (`framework-build-subsystem.md` §9, `.retro-last-run`), überspringt `/retro` stumm → im Report vermerken („Retro-Cooldown aktiv; Lessons noch nicht promotet — `/retro --force` erwägen").
3. **Report + Notification:** strukturierter Abschluss-Report — pro Achse Ist→Ziel + Status (`Done`/`Blocked` + Grund), Liste der offenen agent-flow-Bootstrap-PRs (zum Mensch-Merge), bekannte Restunschärfen (autonom gebootstrappte Packs). Report als Kommentar an ein Tracking-Item. **`PushNotification`** senden (Overnight → Mensch findet morgens das Ergebnis).
4. **Staging-Dir:** kann verworfen werden (`rm -rf .claude/upgrade/<run_id>`) — gebootstrappte Packs leben via die offenen PRs regulär weiter. Bei `status: blocked` **behalten** (Resume braucht ihn).

## Grenzen
- **Eine Major-Stufe je Achse pro Item** — niemals mehrere Majors in einem Schritt (Spec §1).
- **Kein Tool-/Framework-Wechsel**, nur Versions-Modernisierung; keine Auto-Konvertierung.
- **Mergt keine agent-flow-Fabrik-PRs** (Bootstrap-Packs) — Mensch-Gate.
- Gates unverändert hart: reviewer-Drift-Gate, Security-Floor, Template-Diff-Gate, Test-Gate. **Autonomie senkt nie ein Gate.**
- Single-Writer: außer dem initialen Plan-Commit + Item-Anlage + Profil-Rückschreib (begründete Erweiterung, Spec §3/§7) schreibt **`/flow`** Board-Status + Code-PRs.
- Unlösbares wird **Blocked + Report**, nicht erfragt (Autonomie-Posten).
