# Red-Team-Subsystem — autorisiertes Angriffs-Testen der eigenen Apps, das den Sicherheits-Lernkreis schließt

> **Status:** akzeptiert — Fabrik-Seite (Skill + Agent-Verträge, Security-Pack-Härtung) **in Bau** (F-030, F-031).
> **Offen (Cross-Repo, SR-Folge):** die Red-Team-Kachel im dev-gui-„Fabrik"-Panel (§6). Sprach-**neutral**.
> Quer-Achse wie `reconcile-subsystem.md`. Skill (Arbeitstitel) `/agent-flow:red-team`.

## 1. Zweck & Problem

Sicherheitswissen veraltet schneller als jedes andere: neue CVEs, neue Angriffsklassen, neue Norm-Fassungen —
teils täglich. Die Fabrik hält Sprach-/Framework-Wissen über `train` (Netz-Recherche) und `retro`
(Einsatz-Erfahrung) aktuell. Für Sicherheit ist der Kreis heute aber **nur zur Hälfte geschlossen**:

| Quelle | Richtung | Deckt | Lücke |
|---|---|---|---|
| **`train security`** | Netz → Pack | externe Normen/Standards (OWASP, NIST, RFC) | kein Erfahrungs-Rückfluss |
| **`reviewer` → `retro`** | Code-Review → Pack | was im **Diff** auffällt | nur was durch `/flow` läuft; **niemand greift die laufende App an** |
| **Red-Team (dies)** | **Live-Angriff → Pack + Fixes** | echte Lücken der **deployten** App | — |

Es fehlt der **Produzent echter Angriffs-Funde**. Ohne ihn lernt der `security`-Pack nie aus dem, was ein
Angreifer gegen die **laufende** App tatsächlich erreicht. Das Red-Team-Subsystem füllt genau diese Lücke und
klinkt sich in den bestehenden `train`/`retro`-Kreis ein.

## 2. Grundhaltung — Koordination statt Tarnung (verbindlich)

Getestet werden **ausschließlich eigene, autorisierte Apps** des Owners. Die Fähigkeit ist als
**Detection-Koordination** ausgelegt, **nicht** als Detection-Evasion:

- **Keine Tarnung.** Es wird nichts gebaut, das sich heimlich an einem Schutzsystem (Cloudflare/WAF) vorbeischleicht.
  Bei eigener Infrastruktur ist das unnötig **und** liefert schlechtere Daten (man sieht nicht, was die Edge abgefangen hätte).
- **Angekündigte Ausnahme.** Vor einem Lauf wird die Test-Quelle im eigenen Cloudflare-Konto freigeschaltet
  (WAF-Skip/Log-only), danach wieder scharf gestellt. Das ist Koordination, kein Umgehen.
- **Zwei Messpunkte, eine Differenz.** Optimal misst ein Lauf **beides**: durch Cloudflare (= was ein Angreifer real
  erreicht) **und** direkt an den Origin (= was ohne Schutz drin wäre). Die Differenz zeigt, wie viel die Edge abfängt.

## 3. Ziel-Allowlist — konstruktiv erzwungen

Die Fähigkeit kann **konstruktionsbedingt nie** gegen etwas Fremdes feuern. Kein Freitext-Ziel. Die zulässigen
Ziele sind die **Schnittmenge**:

> „läuft als Container auf dem eigenen VPS" **UND** „gehört zu einem eigenen Repo der Org".

Diese Liste wird zur Laufzeit ermittelt (Docker-Blick des VPS ∩ Org-Repos), nicht von Hand gepflegt. Ein Ziel, das
nicht in dieser Schnittmenge liegt, wird **immer** abgewiesen (Default deny). *(Dieselbe localhost-/Origin-Denk­weise
wie `security/R16` beim Admin-Setup.)*

## 4. Ablauf eines Laufs (Fabrik-Seite)

1. **Ziel auflösen + Allowlist-Gate** (§3). Nicht-autorisiertes Ziel → sofort STOPP.
2. **Pack lesen.** `knowledge/security.md` wird geladen — Methodik, Angriffsklassen (OWASP Top 10:2025), stack-spezifische Checks.
3. **Breiter Scan (self-updating).** Etablierter Scanner (Nuclei/OWASP ZAP) gegen das Ziel; die Angriffs-Vorlagen
   werden bei **jedem** Lauf frisch aus dem offiziellen Feed gezogen — die „tagesaktuelle" Ebene ist damit **per
   Konstruktion** aktuell und lebt NICHT im Pack (vgl. `security.md`-Kopf: „tagesaktuelle CVEs → Dependabot + geplanter Scan").
4. **Triage (agentisch).** Ein `claude -p`-Agent mit begrenztem Toolset triagiert die Roh-Funde (False-Positive-Filter,
   Ausnutzbarkeit, Schweregrad), ohne selbst destruktiv zu handeln.
5. **Drei Ausgänge — der Lernkreis:**
   - **Protokoll** — „was versucht / hat gegriffen / wurde abgewehrt" (+ Cloudflare-Differenz, §2). Ein Dokument pro Projekt: `docs/red-team-audit.md` (analog `spec-audit.md`).
   - **Board-Items** — jede bestätigte Lücke wird als To-Do-Item angelegt, damit `/flow` sie behebt (finden → beheben → erneut testen).
   - **Lessons** — wiederkehrende, generalisierbare Muster werden als projekt-lokale Lesson abgelegt (Format wie `.claude/lessons/`), damit **`retro`** sie in die Einsatz-Lane des `security`-Packs (`security/E<NN>`, §5) heben kann.
6. **Freigabe — immer ein PR.** Wie `reconcile`: kein Self-Merge, kein Auto-Feuern. Der Lauf liefert Protokoll + Board-Items als **einen PR** zur Freigabe.

## 5. Lernkreis — wie es an `train`/`retro` andockt

Der `security`-Pack bekommt **zwei kollisionsfreie Lanes** (F-030):

| Lane | Hoheit | Regel-IDs | Quelle |
|---|---|---|---|
| **Norm-Lane** | `train` | `security/R<NN>` | externe Standards (OWASP/NIST/RFC), feste `primary_sources` |
| **Einsatz-Lane** | `retro` | `security/E<NN>` | Erfahrung aus echten Läufen (Red-Team-Funde, Review-Muster) |

So schreibt `train` nie in die Erfahrungs-Regeln und `retro` nie in die Norm-Regeln — analog zur A/B-Trennung der
Framework-Packs. Der Red-Team-Lauf **erzeugt** die Lessons, die `retro` in die Einsatz-Lane destilliert — die dann
den nächsten Lauf schärfen.

## 6. Architektur-Aufteilung (zwei Repos)

Wie beim Reconcile: **dünner Auslöser im dev-gui, gesamte Logik in agent-flow.**

- **agent-flow (dies, F-030/F-031; scharf F-032):** Skill `skills/red-team/SKILL.md` + Agent `agents/red-team.md` + Pack-Härtung. Sprach-neutral, headless-konsumierbar (`claude -p`). **Scharfer Betrieb (F-032):** echter, nicht-destruktiver Nuclei-Lauf (frische Templates pro Lauf) **hinter dem Feuer-Freigabe-Gate** — kein Trockenlauf mehr; Ziel-URL wird server-seitig aus dem Allowlist-Eintrag abgeleitet (Spec R1–R6).
- **dev-gui (gebaut, F-090):** eine **Red-Team-Kachel** im „Fabrik"-Panel, die — genau wie der Reconcile-Button — nur einen Fabrik-Befehl über einen Headless-Runner startet (`HeadlessRedTeamRunner`). Ziel-Auswahl = Allowlist aus §3 (kein Freitext); leitet die Ziel-**URL** server-seitig aus dem Allowlist-Eintrag ab (VPS-Host:hostPort bzw. öffentliche Hostname). Zeigt Protokoll + verlinkt die erzeugten Board-Items. **Cloudflare-Koordination (§2) ist ein vorab menschlich gesetzter Schritt — die Kachel PRÜFT die Ausnahme, SETZT sie NIE selbst** (Standard-Modus `direkt` braucht keine).

## 7. Bewusst NICHT

- **Kein Auto-Feuern gegen Live-Infra.** Der Lauf ist scharf (echter Nuclei-Lauf, F-032), aber jeder Lauf gegen eine laufende App ist eine **per-Lauf menschlich autorisierte** Aktion (Feuer-Freigabe-Gate) — nie ungefragt/automatisch.
- **Keine automatische Cloudflare-Umkonfiguration.** Die Ausnahme setzt der Mensch **vorab**; der Lauf **prüft** sie nur (Spec R5). Standard-Modus `direkt` braucht keine.
- **Keine Detection-Evasion / Tarnung** (§2).
- **Keine fremden Ziele** — konstruktiv ausgeschlossen (§3).
- **Kein destruktives Ausnutzen** — die Triage beweist Ausnutzbarkeit, ohne Schaden anzurichten (kein Datenabfluss, keine Löschung).
- **Keine tagesaktuellen CVEs im Pack** — die gehören in die self-updating Scanner-Feeds + Dependabot (§4.3).

## 8. Touchpoints

- `knowledge/security.md` — zwei Lanes (§5), feste Quellen, 3-Speed-Kopfnote.
- `agents/train.md` — `/train security` respektiert `primary_sources`/`non_sources`.
- `agents/retro.md` — schreibt für den `security`-Domänen-Pack ausschließlich in die Einsatz-Lane (`security/E<NN>`).
- `agents/reviewer.md` — Enforcement der Lane-Trennung.
- `skills/flow/SKILL.md` — Security-Frische-Nudge (§siehe security-pack-freshness).
- `agents/red-team.md`, `skills/red-team/SKILL.md` — die Fähigkeit selbst.
- `docs/red-team-audit.md` (pro Projekt) — Protokoll-Logbuch.
