---
spec_format: use-case-2.0
status: active
---

# Spec: Red-Team-Fabrik-Fähigkeit (Skill + Agent)

> Die Fabrik-Seite der Red-Team-Fähigkeit: ein sprach-neutraler Skill + Agent, der autorisierte eigene Apps testet
> und den Sicherheits-Lernkreis schließt. Bindender Rahmen: `docs/architecture/red-team-subsystem.md`. Feature: F-031.
> **Sicherheits-Grenze:** definiert die *Fähigkeit* (Werkzeug + Verträge), NICHT ein Auto-Feuern gegen Live-Infra.

## Kontext & Motivation

Der `security`-Pack lernt heute nur aus Netz-Recherche (`train`) und Code-Review (`reviewer`→`retro`). Niemand
greift die **laufende** App an. Diese Fähigkeit ist der fehlende Produzent: sie erzeugt echte Angriffs-Funde als
Protokoll + Board-Items + Lessons und dockt so an `retro` an (Einsatz-Lane `security/E<NN>`).

## Akzeptanzkriterien

- **AC1 — Agent-Definition.** `agents/red-team.md` existiert und definiert die Rolle sprach-neutral: liest
  `knowledge/security.md`, steuert einen etablierten Scanner (Nuclei/OWASP ZAP), triagiert die Funde agentisch,
  liefert die drei Ausgänge (Protokoll, Board-Items, Lessons). Tools-Umfang begrenzt (kein destruktives Ausnutzen).
- **AC2 — Skill-Definition.** `skills/red-team/SKILL.md` existiert, dispatcht den Agenten, ist **headless-konsumierbar**
  (`claude -p /agent-flow:red-team …`) und hat einen **verbindlichen Ausgabevertrag** (maschinenlesbares End-JSON
  bei nicht-interaktivem Lauf — Muster wie `from-notes` §Headless-Ausgabevertrag).
- **AC3 — Ziel-Allowlist konstruktiv erzwungen.** Der Skill/Agent akzeptiert **kein** Freitext-Ziel. Zulässig ist
  nur die Schnittmenge „läuft auf dem eigenen VPS" ∩ „eigenes Org-Repo" (`red-team-subsystem.md` §3). Ziel außerhalb
  → sofort STOPP (Default deny).
- **AC4 — Koordination statt Tarnung.** Der Vertrag hält fest: keine Detection-Evasion; Cloudflare-Koordination
  (Freischalten vor Lauf, Scharfstellen danach) ist ein **menschlich bestätigter** Schritt. Optional zwei Messpunkte
  (durch Cloudflare + direkt am Origin) mit Differenz-Ausweis.
- **AC5 — Protokoll-Logbuch.** Jeder Lauf schreibt genau **einen** Block in `docs/red-team-audit.md` (ein Dokument pro
  Projekt, analog `spec-audit.md`): „was versucht / hat gegriffen / wurde abgewehrt" (+ Cloudflare-Differenz). Auch
  ein No-Op-Lauf (keine Funde) wird protokolliert.
- **AC6 — Board-Items + Lessons (Lernkreis).** Bestätigte Lücken werden als To-Do-Board-Items angelegt (für `/flow`);
  generalisierbare Muster werden als projekt-lokale Lesson im `retro`-lesbaren Format abgelegt, die `retro` in die
  Einsatz-Lane `security/E<NN>` heben kann (`red-team-subsystem.md` §5).
- **AC7 — Freigabe immer als PR.** Kein Self-Merge, kein Auto-Feuern; Protokoll + Board-Items landen als **ein** PR
  zur Freigabe (Muster `reconcile`). Ohne Remote/Auth: committeter lokaler Branch als Fallback.
- **AC8 — Verdrahtung.** `AGENTS.md` und `docs/architecture/red-team-subsystem.md` §8 nennen den Agenten/Skill als
  Touchpoint; der Skill ist im Plugin registriert (auffindbar wie die anderen `/agent-flow:*`-Skills).

## Scharfer Betrieb (Real-Execution — F-032)

Ersetzt den Trockenlauf durch einen **echten, nicht-destruktiven** Scanner-Lauf. Das Feuer-Freigabe-Gate + die
Allowlist bleiben unverändert HART.

- **AC9 — Echter Nuclei-Lauf.** Nach bestandenem **Feuer-Freigabe-Gate** (AC4/Agent Schritt 3) führt der Agent einen
  **echten** Nuclei-Lauf gegen die Ziel-URL aus (kein Trockenlauf mehr). Die Angriffs-**Templates** werden **pro Lauf
  frisch** gezogen (self-updating Feed) — die tagesaktuelle Ebene ist damit per Konstruktion aktuell und lebt NICHT im Pack.
- **AC10 — Nicht-destruktiv (HART).** Der Lauf ist auf **Detektion** beschränkt: destruktive/intrusive Template-Klassen
  werden ausgeschlossen (`-exclude-tags dos,intrusive,fuzz`), der Lauf ist **rate-limitiert** und **timeout-begrenzt**.
  Kein eigener Exploit-Code, kein Datenabfluss, keine Persistenz-Änderung am Ziel.
- **AC11 — Funde parsen → Triage.** Die Nuclei-**JSONL**-Ausgabe wird geparst (`template-id`, `info.name`, `info.severity`,
  `matched-at`) und an die agentische Triage übergeben (False-Positive-Filter, Ausnutzbarkeit **belegen** ohne auszunutzen,
  Schweregrad). Ergebnis → Protokoll (`docs/red-team-audit.md`) + Board-Items + Lessons (AC5/AC6).
- **AC12 — Ziel-URL als Eingabe + URL↔Ziel-Bindung (HART).** Skill/Agent nehmen die Ziel-URL(s) als Argument entgegen:
  `url=<origin-url>` (+ `url_edge=<public-url>` bei `modus=beide`). **KEIN Client-Freitext:** die URL wird
  **server-seitig aus dem autorisierten Allowlist-Eintrag abgeleitet** (der Client sendet nur `ziel`; VPS-Host:hostPort
  bzw. öffentliche Hostname). Der **Agent verifiziert**, dass der URL-**Host** zum in Schritt 1 aufgelösten Ziel gehört
  (URL↔Ziel-Bindung) — gehört sie nicht oder fehlt sie für einen scharfen Lauf → **blockiert** (`status: blocked`, kein
  Raten, nie ein Scan gegen eine fremde Adresse). So bleibt die konstruktive Allowlist auch über die URL gewahrt.
- **AC13 — Modus-Semantik + Cloudflare NUR-prüfen (HART).** `direkt` = gegen den **Origin** (sicherer Default, **keine**
  Cloudflare-Änderung nötig). `durch-cloudflare` = gegen die **öffentliche** URL; verlangt eine **vorab** gesetzte
  Ausnahme — der Lauf **PRÜFT** deren Vorhandensein, **SETZT sie NIE selbst**. `beide` = beide Läufe + Differenz-Ausweis.
  Weder Agent noch Kachel ändern jemals die Cloudflare-Konfiguration (Koordination statt Tarnung, menschlich gesetzt).
- **AC14 — Grenzen unverändert.** Feuer-Freigabe-Gate, Allowlist (Default deny), kein destruktives Ausnutzen, immer PR —
  alles bleibt hart. **Kein Auto-Feuern:** jeder scharfe Lauf braucht die per-Lauf-Freigabe.

## Scan hinter der Cloudflare-Access-Wall (Service-Token-Protokoll — F-032-Erweiterung)

Manche autorisierten Ziele stehen hinter einer **Cloudflare-Access-Wall**: ein anonymer Nuclei-Lauf gegen die
öffentliche URL trifft nur die Access-Login-Seite, nie die App. Damit ein scharfer Lauf diese Wall **legitim**
(Koordination statt Tarnung, AC4) passieren kann, führt der Konsument (dev-gui, `docs/specs/red-team-scan-access-token.md`
Story **S-407** — Auftraggeber/Gegenstück dieses Vertrags) ein **Cloudflare-Access-Service-Token-Protokoll** ein. Diese
AC hält die agent-flow-Seite (Konsum) dieses Protokolls bindend fest. Sie ist **rein additiv** — ohne den Marker bleibt
das Verhalten aus AC1–AC14 **bit-identisch** (kein Regress).

- **AC15 — Cloudflare-Access-Service-Token-Protokoll konsumieren (HART).**
  - **(a) Marker parsen + durchreichen (Skill).** `skills/red-team/SKILL.md` akzeptiert einen **optionalen** argv-Token
    `access_header=cf-access`. Er ist **kein Geheimnis**, nur ein Signal-Marker. Der Skill parst ihn (§1) und reicht ihn
    im Dispatch-Block (§3) als zusätzliches Feld an den Agenten durch: `access_header: cf-access | (none)`. **Enum-Guard**
    wie bei `modus=`: **einziger** zulässiger Wert ist `cf-access`; jeder andere Wert → **klarer Abbruch, kein Dispatch**.
    Fehlt der Marker (Normalfall, alle heutigen Aufrufe) → Feld `(none)`, Verhalten unverändert.
  - **(b) Header injizieren (Agent, Nuclei-Lauf).** Ist `access_header: cf-access` im Dispatch gesetzt, schickt der echte
    Nuclei-Lauf (`agents/red-team.md` §Vorgehen Schritt 3, AC9/AC10) **zwei zusätzliche HTTP-Header** mit:
    `CF-Access-Client-Id` und `CF-Access-Client-Secret`. Deren Werte liest der Lauf **ausschliesslich aus der
    Prozess-Umgebung** (`CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET`, vom Konsumenten als Pro-Lauf-Env-Override
    injiziert). Die Werte werden **NIE** in die Kommandozeile selbst eingebettet, geloggt oder über `set -x`/Debug-Ausgabe
    sichtbar gemacht — sie erscheinen **nur** als ausgehende Request-Header. Der übrige Nuclei-Aufruf (Ziel-URL,
    `-exclude-tags dos,intrusive,fuzz`, Rate-Limit, Timeout, JSONL-Ausgabe) bleibt unverändert (AC9/AC10 gelten fort).
  - **(c) Graceful-Blocked statt ungeschütztem Scan (HART).** Ist `access_header: cf-access` gesetzt, aber
    `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` sind in der Prozess-Umgebung **nicht vorhanden** (leer/fehlend) → der
    Agent bricht **nicht** den ganzen Lauf ab, sondern degradiert klar zu `status: blocked` (Muster: `url=`-Pflichtfeld-
    Blockade AC12) mit dem Grund **„Cloudflare-Access-Header angefordert, aber kein Token in der Umgebung — Scan hinter der
    Wall nicht möglich"**. **Kein stiller Fallback** auf einen anonymen/ungeschützten Scan gegen die Wall.
  - **(d) Security-Floor für die Token-Werte (HART, wie AC5/AC10/AC14).** Die beiden Token-Werte
    (`CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET`) dürfen **NIEMALS** erscheinen in: `docs/red-team-audit.md`, den drei
    Lernkreis-Ausgängen (Protokoll/Board-Items/Lessons), dem headless End-JSON, Board-Items oder **irgendeiner**
    Bash-Ausgabe/Log-Zeile — **ausschliesslich** als ausgehende HTTP-Request-Header (b).
  - **(e) Kein Regress ohne Marker.** Ohne `access_header=cf-access` (Normalfall) werden weder die Env-Header noch die
    Blocked-Prüfung aus (c) aktiv; jeder heutige Aufruf verhält sich **bit-identisch** zu AC1–AC14.

## Bewusst NICHT (Sicherheits-Grenze)

- **Kein Auto-Feuern.** Das *Feuern* gegen eine laufende App bleibt eine **per-Lauf menschlich autorisierte** Aktion
  (Freigabe-Gate in der Kachel/CLI) — der Lauf ist real, aber nie ungefragt/automatisch.
- **Keine Detection-Evasion / Tarnung** — nur Koordination (§AC4).
- **Keine fremden Ziele** — konstruktiv ausgeschlossen (§AC3).
- **Kein destruktives Ausnutzen** — Ausnutzbarkeit wird belegt, nicht ausgenutzt (AC10).
- **Keine automatische Cloudflare-Umkonfiguration** — die Ausnahme setzt der Mensch, der Lauf prüft sie nur (AC13).
- **Kein Token-Beschaffen / -Rotieren durch den Agenten (AC15).** Der Agent **konsumiert** nur die vom Konsumenten
  (dev-gui) als Pro-Lauf-Env injizierten Access-Service-Token-Werte; er erzeugt, rotiert oder persistiert sie nie und
  gibt sie nie über einen anderen Kanal als die zwei ausgehenden HTTP-Header weiter. Ohne Token in der Umgebung →
  `status: blocked` (AC15c), **nie** ein anonymer Scan gegen die Access-Wall (keine Tarnung).
