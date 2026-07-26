---
id: git-auth-hardening
title: git-Auth dauerhaft robust in ensure-gh-auth.sh (kein Token in Dateien)
status: active
version: 1
spec_format: use-case-2.0
area: auslieferung
---

# Spec: git-Auth-Härtung ohne Token-Persistenz  (`git-auth-hardening`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Einordnung.** Härtet `scripts/ensure-gh-auth.sh` (heute: `gh auth login --with-token` + `gh auth setup-git`) so, dass git-Push/Fetch **zuverlässig** funktioniert, **ohne je ein Token in eine Datei/Config zu schreiben**. Löst den belegten Vorfall vom 23.07.: der flow/L05-Workaround schrieb den ~1h gültigen App-Token als `http.https://github.com/.extraheader` in `.git/config` des Hauptordners; nach Ablauf blockierte der Header vom 23.–26.07. **jede** git-Netzwerkoperation aller Sessions und Nacht-Drains mit „Invalid username or token", bis er am 26.07. manuell entfernt wurde.

## Zweck
`ensure-gh-auth.sh` stellt einen funktionierenden git-Push-/Fetch-Weg über HTTPS her, ohne ein Token in Datei, Config oder Log zu persistieren (harte Owner-Regel: niemals Secrets in Dateien/Configs). Dazu (a) ein korrektes Credential-Helper-Setup, das den bekannten Bot-Login-Bug umschifft, indem es `x-access-token` als Username erzwingt, während das Token **on-demand** je git-Aufruf aus `gh` gestreamt und nie geschrieben wird; (b) Selbstheilung, die vorhandene/veraltete `http.*.extraheader`-Einträge in der Repo-Config erkennt und entfernt; (c) Korrektur des flow/L05-Lesson-Texts und etwaiger `agents/cicd.md`/`board-ship.sh`-Hinweise, die genau dieses Anti-Pattern empfehlen.

## Main Success Scenario
1. `ensure-gh-auth.sh` läuft (idempotent, aus `board-ship.sh`/Flow heraus, headless). Es mintet wie bisher den App-Token und loggt `gh` persistent ein (`~/.config/gh`, ~1h gültig).
2. **Selbstheilung zuerst:** das Skript erkennt und entfernt vorhandene/veraltete `http.*.extraheader`-Einträge aus der Repo-Config des aufrufenden Working-Trees/Worktrees (Reste des alten Workarounds), bevor es den Credential-Weg einrichtet.
3. **Credential-Helper mit erzwungenem Username:** statt (oder zusätzlich zu) `gh auth setup-git` konfiguriert das Skript einen git-Credential-Helper (auf Basis `gh auth git-credential`), der bei jedem git-Netzwerkaufruf `username=x-access-token` liefert — auch wenn die GitHub-App-Installation sonst den Bot-Login als Username zurückgäbe. Das Token wird vom Helper **gestreamt**, nie in eine Datei geschrieben.
4. git-Push und git-Fetch über HTTPS gelingen — ohne `extraheader`, ohne Credential-Store-Datei mit Token-Inhalt.

## Alternative Flows
### A1: Bot-Login-Username statt `x-access-token`
- Ohne Fix liefert der Helper manchmal den Bot-Login als Username → `Invalid username or token`. Der Wrapper überschreibt die `username=`-Zeile der Helper-Ausgabe auf `x-access-token`, sodass der Push gelingt, wo der rohe `gh auth setup-git`-Pfad scheiterte.

### A2: Poisoned Config aus altem Workaround
- Die Repo-Config trägt noch einen abgelaufenen `http.https://github.com/.extraheader`-Eintrag (der den Ordner vergiftet). Die Selbstheilung (Schritt 2) entfernt ihn, bevor der neue Weg greift — ohne Owner-Eingriff.

### E1: Kein Token mintbar
- `.env.gpg`/`gpg.pass` nicht verfügbar → `GH_TOKEN` nicht gemintet: das Skript beendet wie bisher mit Klartext-Fehler und Exit 1 (unverändertes bestehendes Verhalten). Kein Fallback auf einen persistierten Header.

## Acceptance-Kriterien

- **AC1** — Tokenloser Push-/Fetch-Weg: nach dem Lauf funktionieren `git push` **und** `git fetch` über HTTPS gegen GitHub, **ohne** dass irgendein Token in eine Datei/Config geschrieben wurde. Prüfbar: die Repo-Config enthält **kein** `http.*.extraheader`, und keine Credential-Store-Datei enthält den Token-Klartext. *(Security-AC — Trust-Boundary Secret-Persistenz)*
- **AC2** — Credential-Helper mit erzwungenem Username: das Setup konfiguriert einen git-Credential-Helper (auf Basis `gh auth git-credential`), der zuverlässig `x-access-token` als Username liefert — auch wenn die GitHub-App-Installation den Bot-Login zurückgäbe (Bot-Login-Bug umschifft, z.B. per Helper-Wrapper). Das Token wird on-demand je git-Aufruf gestreamt, **nie** auf Platte geschrieben.
- **AC3** — Selbstheilung `extraheader`: das Skript erkennt und entfernt vorhandene/veraltete `http.https://github.com/.extraheader` (und jeden `http.*.extraheader`)-Eintrag aus der Repo-lokalen git-Config des aufrufenden Working-Trees/Worktrees, **bevor** es den Credential-Weg einrichtet. Eine durch den alten Workaround vergiftete Config wird automatisch bereinigt. *(deckt A2)*
- **AC4** — Idempotenz: wiederholte Läufe sind gefahrlos (keine doppelte Config, kein Fehler wenn nichts zu bereinigen ist); ein bereits gesundes Setup bleibt unverändert (konsistent mit dem bestehenden „idempotent"-Vertrag des Skripts).
- **AC5** — Lesson-/Doku-Korrektur: der flow/L05-Lesson-Text wird korrigiert — die `extraheader`-Token-Workaround-Empfehlung wird **entfernt** und durch den Verweis auf den tokenlosen Credential-Helper-Weg ersetzt. Etwaige Anti-Pattern-Hinweise in `agents/cicd.md`/`scripts/board-ship.sh` werden ebenso korrigiert (falls vorhanden). **Kein** Dok empfiehlt danach noch, ein Token in eine Datei/Config zu schreiben.
- **AC6** — Kein Secret in Datei/Log: weder das Token noch eine base64-Kodierung davon wird in eine Datei, Config oder ein committetes Artefakt geschrieben; Log-Ausgaben maskieren jeden Token-Wert. *(Security-AC — Owner-Secrets-Regel)*
- **AC7** — Bot-Login-Bug abgedeckt: liefert der Credential-Helper sonst den Bot-Login als Username → der Wrapper erzwingt `x-access-token`; der Push gelingt dort, wo der rohe Pfad mit „Invalid username or token" scheiterte. *(deckt A1)*
- **AC8** — Headless / kein manueller Eingriff: der gesamte Weg funktioniert headless innerhalb eines `/flow`-/Nacht-Drain-Laufs — keine manuelle Token-Eingabe, kein interaktiver Prompt.
- **AC9** — Fehlerpfad unverändert: ohne mintbaren Token beendet das Skript weiterhin mit Klartext-Fehler + Exit 1, **ohne** Fallback auf einen persistierten Header. *(deckt E1)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace git-auth-hardening#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Da agent-flow `language: md` ist, werden die
> Skript-Anteile — soweit mechanisch — über ein Smoke-Skript belegt (z.B. „Config trägt nach
> Lauf kein extraheader", „stale extraheader wird entfernt"), die Doku-/Lesson-Korrektur als
> Doku-Inspektion.

## Verträge

### `scripts/ensure-gh-auth.sh` — erweitertes Verhalten
1. Token minten + `gh auth login --with-token` (unverändert).
2. **Selbstheilung:** `git config --unset-all http.https://github.com/.extraheader` (und generisch alle `http.*.extraheader`) in der Repo-Config des aufrufenden Repos entfernen — idempotent (kein Fehler, wenn nicht vorhanden).
3. **Credential-Helper einrichten:** einen Helper konfigurieren (repo- oder global-scope, **nur Helper-Pfad, kein Secret**), der `gh auth git-credential` nutzt und die `username=`-Ausgabe auf `x-access-token` normalisiert (Wrapper). Beispiel-Vertrag des Wrappers: liest die git-Credential-Anfrage, ruft `gh auth git-credential get`, ersetzt `username=<botlogin>` durch `username=x-access-token`, gibt `password=<token>` unverändert weiter — alles über stdin/stdout, keine Datei.
4. Erfolgsmeldung ohne Token-Wert.

### Was NIE geschrieben wird (Negativ-Vertrag)
- **Kein** `http.*.extraheader` in irgendeiner git-Config.
- **Keine** `credential.helper store`-Datei (`~/.git-credentials`) mit Token-Klartext.
- **Kein** Token/base64 in Log, Datei oder Commit.

## Edge-Cases & Fehlerverhalten
- **Token-Ablauf mitten in der Session:** der Helper streamt bei jedem git-Aufruf aus der aktuellen `gh`-Auth; ein erneuter `ensure-gh-auth.sh`-Lauf (Re-Login) frischt die `gh`-Auth auf. Kein stale-File-Zustand kann git blockieren (im Gegensatz zum alten `extraheader`).
- **Mehrere Worktrees:** die Selbstheilung bereinigt die Config des **aufrufenden** Repos; der Helper wird so gesetzt, dass er für alle Worktrees greift (global-scope Helper) — ein in einem Worktree gesetzter `extraheader` wird beim nächsten Lauf in diesem Worktree bereinigt.
- **Vorhandener fremder Helper:** ist bereits ein anderer, funktionierender Helper gesetzt, überschreibt das Skript ihn nicht destruktiv, sondern ergänzt den erzwungenen-Username-Weg idempotent (kein Doppel-Eintrag, AC4).

## NFRs
- **Sicherheit (hart):** keine Secret-Persistenz in Dateien/Configs/Logs (AC1/AC6) — die zentrale Owner-Regel, deren Verletzung den 3-Tage-Ausfall auslöste.
- **Robustheit:** self-healing gegen vergiftete Configs (AC3); headless (AC8); kein stale-File-Fenster (Edge-Case Token-Ablauf).
- **Idempotenz:** wiederholte Läufe unschädlich (AC4).

## Nicht-Ziele
- **Keine** Änderung des Token-Mintings (`.env.gpg`/`gpg.pass`-Pfad, load-env.sh) — nur der git-Credential-Weg.
- **Keine** SSH-Umstellung (bleibt HTTPS + App-Token).
- **Keine** Änderung an `gh`-eigener Persistenz (`~/.config/gh` bleibt der `gh`-Login-Store — das ist gh-Standard, kein von uns geschriebenes Secret-File).

## Abhängigkeiten
- `scripts/ensure-gh-auth.sh` (Kern), `scripts/board-ship.sh` (Aufrufer `ensure_gh_auth`), `agents/cicd.md` (Hinweis-Korrektur falls vorhanden), `.claude/lessons/flow.md` flow/L05 (Anti-Pattern-Text korrigieren).
- `scripts/load-env.sh` — Token-Minting-Quelle (unverändert).
- Belege: `.claude/lessons/flow.md` flow/L05 (Workaround-Text), `.claude/memory.md` (Offene Fäden — 23.–26.07. Ausfall durch abgelaufenen `http.extraheader`-Token).
