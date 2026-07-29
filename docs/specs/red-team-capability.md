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

## Phase B — Strix gegen Wegwerf-Kopie (aktives Ausnutzen auf isolierter lokaler Kopie — F-035)

> **Erweitert den Lauf um eine zweite Phase im SELBEN Aufruf.** Der bestehende Nuclei-Pfad wird zu **Phase A** und
> bleibt **HART unverändert** (AC9–AC14, Allowlist, „kein destruktives Ausnutzen gegen Produktion"). **Phase B** feuert
> zusätzlich das Exploit-fähige, externe **Strix**-CLI (`usestrix/strix`) — aber **ausschliesslich gegen eine
> wegwerfbare, isolierte lokale Kopie** der App (über `/agent-flow:preview`), auf der aktives Ausnutzen unbedenklich
> ist. Rahmen: `docs/architecture/red-team-subsystem.md` §9. Beide Phasen fliessen in dieselben drei Lernkreis-Ausgänge,
> jeder Fund mit **Quelle-Markierung**. Strix ist eine **externe Abhängigkeit** (eigenes Docker-Image, eigener
> LLM-API-Key) — **gepinnt**, bewusst gebumpt über `/agent-flow:upgrade`.

- **AC15 — Zwei Phasen in EINEM Aufruf.** Ein `/agent-flow:red-team`-Aufruf führt **Phase A** (Nuclei gegen die echte
  laufende Produktions-App, AC9–AC14, unverändert) und **danach Phase B** (Strix) aus — **kein** zweiter Skill/Auslöser,
  **kein** manueller Zwischenschritt für den Owner. Ein Knopfdruck/Aufruf löst beide Phasen aus.
- **AC16 — Phase A unangetastet (HART).** Nuclei-Pfad, Ziel-Allowlist (AC3/AC12), URL↔Ziel-Bindung und
  „**kein destruktives Ausnutzen** gegen Produktion" (AC10) bleiben **exakt** wie bisher. Phase B ändert daran nichts;
  sie läuft **additiv danach** und niemals gegen die Produktions-Adresse.
- **AC17 — Wegwerf-Kopie via `preview` (HART).** Phase B startet die App zuerst als **isolierte lokale Kopie** über
  `/agent-flow:preview up` (produktives ghcr-Image, **frische/leere migrierte Test-DB**, eigenes Docker-Network/Volume —
  `skills/preview/SKILL.md`) und richtet Strix **ausschliesslich** gegen die lokale Preview-Adresse
  (`http://localhost:<preview_port>`). Strix erhält **nie** die Produktions-Adresse — die Ziel-Bindung ist konstruktiv
  auf die Preview-URL beschränkt.
- **AC18 — Aufräum-Garantie (HART).** Nach Phase B läuft **immer** `/agent-flow:preview down` — auch bei
  Strix-Fehler/Abbruch/Timeout (Cleanup im Fehlerpfad, z.B. `trap`/`finally`-Muster). Es bleiben **keine verwaisten**
  Preview-Container/Volumes/Netze zurück.
- **AC19 — Aktives Ausnutzen NUR auf der Kopie.** Auf der Wegwerf-Kopie **DARF** Strix aktiv ausnutzen (funktionierende
  PoC-Exploits: SQLi, RCE, XSS, Business-Logic etc.), weil **keine echten Daten** und **keine Produktion** betroffen
  sind. Die „kein destruktives Ausnutzen"-Grenze der Basis-Spec (AC10) gilt **unverändert** für Phase A/Produktion —
  Phase B **unterläuft sie nicht**; sie greift auf der isolierten Kopie schlicht nicht.
- **AC20 — Strix-Version gepinnt (HART).** Strix läuft auf einer **fest gepinnten** Version (**kein** „immer neueste").
  Die gepinnte Version steht an genau **EINER** dokumentierten Stelle (Konstante im red-team-Subsystem/Skill,
  `red-team-subsystem.md` §9) und wird **nur bewusst** über `/agent-flow:upgrade` gebumpt (AC29). Ein Lauf zieht
  **nie** automatisch eine neuere Strix-Version (Risiko: eine neue Version könnte sich unbemerkt aggressiver verhalten).
- **AC21 — Strix-LLM-Key als Secret (HART).** Strix' **eigener** LLM-API-Key (getrennt von den Fabrik-Modellcalls)
  kommt aus dem **bestehenden** Secret-Handling (`.env.gpg` via `scripts/load-env.sh`; Key-Name `STRIX_LLM_API_KEY`)
  und wird als **Env-Variable** in den Strix-Container gereicht — **nie** Klartext auf Platte, in Logs, in der Ausgabe
  oder in Commits (maskiert, analog dem übrigen Secret-Umgang der Fabrik).
- **AC22 — Graceful Skip (kein harter Abbruch).** Fehlt **Docker**, fehlt **`STRIX_LLM_API_KEY`**, oder ist der Lauf
  **repo-los** (kein Profil / kein ghcr-Image für `preview`) → **Phase B wird sauber übersprungen**; **Phase A läuft
  normal weiter**. Eine sichtbare **Warn-Zeile** erscheint im Protokoll-Block **und** im headless-JSON
  (`phase_b: skipped` mit Grund). Der Gesamtlauf bricht **nicht** ab.
- **AC23 — Expliziter Opt-out.** Das Skill-Argument **`phase_b=aus`** deaktiviert Phase B **bewusst** (nur Phase A).
  Default **`phase_b=an`**. Ein unzulässiger Wert → klarer Abbruch der Signatur-Prüfung, **kein** Dispatch (Muster der
  bestehenden `modus=`-Validierung).
- **AC24 — Quelle-Markierung in allen drei Ausgängen (HART).** Jeder Fund trägt **klar** seine Quelle, weil beide
  unterschiedlich zu werten sind:
  - **„Produktion (Nuclei)"** → *real bestätigt, nicht ausgenutzt* (belegte Ausnutzbarkeit gegen die echte App).
  - **„Wegwerf-Kopie (Strix)"** → *aktiv ausgenutzt/bewiesen, aber nur auf der lokalen Kopie geprüft — **nicht**
    zwingend schon über die echte Produktions-Adresse verifiziert*.
  Die Markierung erscheint in **allen drei** Ausgängen: Protokoll-Block, Board-Items **und** Lessons.
- **AC25 — Protokoll-Blockformat erweitert.** Der **eine** Block pro Lauf (`docs/red-team-audit.md`, AC5) bekommt
  getrennte Abschnitte **Phase A** / **Phase B** mit der Quelle-Kennzeichnung (AC24); ein **No-Op je Phase** wird
  **getrennt** ausgewiesen. Es bleibt bei **genau EINEM** Block pro Lauf (append-only, auch bei No-Op beider Phasen).
- **AC26 — Headless-JSON erweitert (rückwärtskompatibel).** Das End-JSON (`skills/red-team/SKILL.md` §5) bekommt ein
  **`phase_b`**-Objekt: `{"status": "ran"|"skipped"|"blocked", "reason": <str|null>, "findings_count": <int>}`. Die
  bestehenden Top-Level-Felder (`status`, `pr`, `findings_count`, `audit_block`, `retro_recommended`) bleiben
  **unverändert**; `findings_count` top-level = Summe der als Board-Items angelegten bestätigten Funde **beider** Phasen.
- **AC27 — Board-Items je Phase mit Quelle.** Bestätigte Lücken **beider** Phasen werden weiterhin als **To-Do**-Items
  angelegt (AC6), jedes mit **Quelle-Vermerk** (AC24). Strix-Funde tragen zusätzlich den Hinweis „**auf Wegwerf-Kopie
  bewiesen — Produktions-Verifikation offen**", damit `/flow` die andere Beweislage kennt.
- **AC28 — Kosten-Hinweis.** Da Strix **eigene** LLM-Calls macht (separate, vom Fabrik-Budget **getrennte** Kosten),
  weist der Lauf **vor** Phase B einen **Kosten-Hinweis** aus (interaktive Ausgabe **und** Protokoll-Block).
- **AC29 — `/upgrade`-Bump-Pfad.** Die gepinnte Strix-Version (AC20) ist als **bewusst bumpbare externe Abhängigkeit**
  über `/agent-flow:upgrade` behandelbar; ein Bump ist **immer ein PR** (kein Self-Merge, kein stiller Sprung).
  `docs/architecture/upgrade-subsystem.md` nennt Strix als solche **gepinnte Tool-Abhängigkeit**.

### Phase B — Edge-Cases & NFR

- **Preview startet nicht** (Image-Pull scheitert, Smoke ≠ 200) → Phase B gilt als **skipped** mit Grund (AC22), Phase A
  bleibt gültig; kein verwaister Stack (AC18-Cleanup greift auch hier).
- **Strix-Timeout / Hänger** → hartes Zeitlimit für den Strix-Lauf; danach Cleanup + `phase_b: {"status":"ran"}` mit
  Teil-Funden bzw. `skipped`-Grund „timeout", nie ein blockierter Gesamtlauf.
- **Doppelte Funde** (dieselbe Klasse in Phase A *und* B) werden **nicht** dedupliziert — die unterschiedliche Quelle/
  Beweislage (AC24) ist bedeutungstragend und bleibt sichtbar.
- **NFR Sicherheit:** Strix bekommt **nur** die Preview-URL (AC17) — konstruktiv unmöglich, dass es die Produktions-App
  ausnutzt. Der LLM-Key bleibt maskiert (AC21).
- **NFR Kosten:** Phase B ist optional abschaltbar (AC23) und wird bei fehlenden Voraussetzungen übersprungen (AC22) —
  keine überraschenden LLM-Kosten ohne Voraussetzung/Hinweis (AC28).

## Bewusst NICHT (Sicherheits-Grenze)

- **Kein Auto-Feuern.** Das *Feuern* gegen eine laufende App bleibt eine **per-Lauf menschlich autorisierte** Aktion
  (Freigabe-Gate in der Kachel/CLI) — der Lauf ist real, aber nie ungefragt/automatisch.
- **Keine Detection-Evasion / Tarnung** — nur Koordination (§AC4).
- **Keine fremden Ziele** — konstruktiv ausgeschlossen (§AC3).
- **Kein destruktives Ausnutzen** — Ausnutzbarkeit wird belegt, nicht ausgenutzt (AC10).
- **Keine automatische Cloudflare-Umkonfiguration** — die Ausnahme setzt der Mensch, der Lauf prüft sie nur (AC13).
- **Kein Strix gegen Produktion (HART, Phase B).** Strix erhält konstruktiv **nur** die lokale Preview-URL (AC17) —
  aktives Ausnutzen findet **ausschliesslich** auf der wegwerfbaren Kopie statt, nie gegen die echte laufende App.
- **Kein Auto-Update von Strix.** Die externe Strix-Version ist **gepinnt** (AC20) und wird nur bewusst über
  `/agent-flow:upgrade` gebumpt (AC29) — nie „immer neueste".
- **Kein zweiter Auslöser / kein separates Plugin** — Phase B ist eine **Erweiterung** des bestehenden Red-Team-Ablaufs
  (ein Aufruf startet beide Phasen, AC15), kein eigener Skill.
