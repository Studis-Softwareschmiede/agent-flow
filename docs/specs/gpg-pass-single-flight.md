---
id: gpg-pass-single-flight
title: provision-gpg-pass.sh — Single-Flight-Lock + sessions-übergreifender Cache gegen parallele Bitwarden-Logins
status: active
area: auslieferung
version: 1
spec_format: use-case-2.0
---

# Spec: GPG-Passphrase Single-Flight  (`gpg-pass-single-flight`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut daraus), `tester` (prüft die AC), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck

`scripts/provision-gpg-pass.sh` macht pro Cache-Miss einen **vollen Bitwarden-Login-Zyklus** (via dev-gui-Container: `bw login --apikey` → unlock → get → logout). Bitwarden verschickt pro API-Key-Login eine Benachrichtigungs-Mail. Beim parallelen Fan-out (Vorfall 2026-07-21: `/train` für alle Packs, 30 gleichzeitige Agenten) rennen alle Aufrufer am noch leeren Cache vorbei und lösen je einen eigenen Login aus → Mail-Schwall beim Owner + unnötige Rate-Limit-Last. Ziel: **N parallele Aufrufer ⇒ genau 1 Login**; alle anderen warten auf den gefüllten Cache.

## Main Success Scenario
1. N Prozesse rufen das Skript (gleiche App) quasi-gleichzeitig auf; der Cache ist leer/abgelaufen.
2. Genau ein Prozess gewinnt das Lock, führt den Container-Roundtrip aus und füllt die Cache-Datei atomar.
3. Alle anderen Prozesse warten (Poll auf Cache ODER Lock-Freigabe) und liefern anschließend den Cache-Pfad — **ohne** eigenen Container-Roundtrip.

## Alternative Flows
### A1: Cache frisch
- Aufrufer liefert sofort den Cache-Pfad (heutiges Verhalten, unverändert — kein Lock nötig).

### E1: Lock-Halter stirbt (Crash, kill)
- Wartende erkennen das verwaiste Lock über sein Alter (Stale-Schwelle) und übernehmen/brechen es; kein Deadlock.

### E2: Warte-Timeout überschritten
- Der Wartende bricht mit Exit ≠ 0 und ohne Ausgabe ab — die bestehende Fallback-Kette des Aufrufers (statische `gpg.pass`) greift wie bei jedem anderen Fehlschlag.

## Acceptance-Kriterien

- **AC1 — Single-Flight-Lock.** Vor dem Container-Roundtrip (Skript-Schritt 3/4) erwirbt der Aufrufer ein exklusives, **per-App** gescoptes Lock (portabel, z. B. `mkdir`-Lock — kein `flock`-Zwang, muss auf macOS + Linux ohne Zusatz-Tools funktionieren). Nur der Lock-Halter führt den Bitwarden-Roundtrip aus; er gibt das Lock in **jedem** Ausgang wieder frei (`trap` auch für Fehlerpfade).
- **AC2 — Warte-Pfad statt Zweit-Login.** Aufrufer, die das Lock nicht bekommen, pollen (kurzes Intervall) auf (a) frische Cache-Datei → Pfad ausgeben, Exit 0; (b) Lock-Freigabe ohne Cache → ein eigener Versuch (sie werden neuer Lock-Halter). Ein Warte-Timeout (Default ~90 s, via Env übersteuerbar) begrenzt das Warten → E2.
- **AC3 — Stale-Lock-Übernahme.** Ein Lock älter als die Stale-Schwelle (Default ≥ Warte-Timeout) gilt als verwaist und wird gebrochen/übernommen (→ E1). Kein Aufrufer wartet unbegrenzt auf einen toten Halter.
- **AC4 — Sessions-übergreifend stabiler Cache-/Lock-Ort.** Cache und Lock leben an einem **deterministischen, nutzer-privaten** Ort (0700-Verzeichnis), der NICHT vom session-spezifischen `$TMPDIR` abhängt (heute läuft der Cache bei per-Session-TMPDIRs ins Leere — parallele Agenten sehen einander nicht). Auflösung: `GPG_BW_CACHE_DIR` (Env) > fester nutzer-privater Default. Datei-Rechte bleiben 0600, Atomik (tmp + `mv`) bleibt erhalten (→ BR: bestehende Secrets-Doktrin, keine Passphrase in Logs/stdout außer als Datei-Pfad).
- **AC5 — Einzelaufruf-Verhalten unverändert.** Interface bleibt bitgenau: stdout = Cache-Pfad bei Erfolg, keine Ausgabe + Exit ≠ 0 bei Fehlschlag; App-Slug-Auflösung, Item-Konvention, TTL-Mechanik (`GPG_BW_TTL_MIN`), dev-gui-Container-Boundary und die Aufrufer-Fallback-Kette (statische `gpg.pass`) bleiben unangetastet.
- **AC6 — Testbarkeit + Parallel-Beweis.** Der Container-Roundtrip ist über einen Test-Hook ersetzbar (z. B. Env `GPG_BW_FETCH_CMD`, nur für Tests; Default = bisheriger `docker exec`-Pfad). Ein selbst-enthaltener Test (`tests/gpg-pass/`, ohne Docker/Bitwarden/Netz) startet ≥ 10 parallele Aufrufe gegen einen **zählenden** Mock-Fetch und beweist: genau **1** Fetch-Ausführung, alle Aufrufer liefern denselben gültigen Cache-Pfad, Exit 0. Zusatzfälle: Stale-Lock wird übernommen (AC3), Timeout liefert Exit ≠ 0 (E2).

## Verträge
- **Betroffene Datei:** `scripts/provision-gpg-pass.sh` (+ neuer Test unter `tests/gpg-pass/`). Keine Änderung an Aufrufern (`scripts/_lib.sh` `resolve_pass_file`), keine Änderung an dev-gui.
- **Env-Parameter (neu, alle optional):** `GPG_BW_CACHE_DIR` (Cache-/Lock-Ort), `GPG_BW_WAIT_SEC` (Warte-Timeout), `GPG_BW_FETCH_CMD` (Test-Hook). Bestehende (`GPG_BW_APP`, `GPG_BW_TTL_MIN`, `DEVGUI_CONTAINER`) unverändert.

## Edge-Cases & Fehlerverhalten
- **E3 — Fetch des Lock-Halters schlägt fehl:** Lock freigeben, kein Cache geschrieben; Wartende dürfen genau einen eigenen Versuch machen (AC2b) — keine Endlos-Retry-Schleife, kein Login-Sturm (max. sequentielle Einzelversuche).
- **E4 — Zwei Apps parallel:** Locks sind per-App gescopt; verschiedene Apps blockieren einander nicht.

## NFRs
- Sicherheit: Passphrase erscheint weiterhin nie auf stdout/in Logs (nur der Datei-Pfad); Cache-Verzeichnis nutzer-privat (0700), Dateien 0600.
- Latenz: Cache-Hit-Pfad bleibt O(Dateisystem-Check); Warte-Poll-Intervall ≤ 1 s.

## Nicht-Ziele
- **Keine** Änderung an der Bitwarden-Boundary-Doktrin (dev-gui-Container bleibt die einzige Bitwarden-Stelle; agent-flow spricht weiterhin nie selbst mit einem Bitwarden-Konto).
- **Keine** Session-Persistenz über die TTL hinaus, kein Daemon, kein Keychain-Umbau.
- **Keine** Drosselung des `/train`-Fan-outs selbst (separates Thema auf Skill-Ebene).

## Abhängigkeiten
- Bestehende Secrets-/Auth-Kette (`docs/architecture/secrets-subsystem.md`, `scripts/_lib.sh`).
