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

## Bewusst NICHT (Sicherheits-Grenze)

- **Kein Auto-Feuern.** Das *Feuern* gegen eine laufende App bleibt eine **per-Lauf menschlich autorisierte** Aktion
  (Freigabe-Gate in der Kachel/CLI) — der Lauf ist real, aber nie ungefragt/automatisch.
- **Keine Detection-Evasion / Tarnung** — nur Koordination (§AC4).
- **Keine fremden Ziele** — konstruktiv ausgeschlossen (§AC3).
- **Kein destruktives Ausnutzen** — Ausnutzbarkeit wird belegt, nicht ausgenutzt (AC10).
- **Keine automatische Cloudflare-Umkonfiguration** — die Ausnahme setzt der Mensch, der Lauf prüft sie nur (AC13).
