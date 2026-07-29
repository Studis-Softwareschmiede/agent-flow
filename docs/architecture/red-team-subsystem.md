# Red-Team-Subsystem — autorisiertes Angriffs-Testen der eigenen Apps, das den Sicherheits-Lernkreis schließt

> **Status:** akzeptiert + **gebaut**. Fabrik-Seite (F-030/F-031) inkl. **scharfem Betrieb** (echter, nicht-destruktiver
> Nuclei-Lauf hinter dem Feuer-Freigabe-Gate, **F-032**). Die Red-Team-Kachel im dev-gui-„Fabrik"-Panel ist **gebaut**
> (**F-090**, §6). Sprach-**neutral**. Quer-Achse wie `reconcile-subsystem.md`. Skill `/agent-flow:red-team`.

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
7. **Folge-Schritt — Retro-Auslöser bei generischen Funden (AC3).** Enthält der Lauf mindestens einen **generisch/universell** klassifizierten Fund, **empfiehlt** der Agent nach dem Landen des PRs einen **`/retro`-Lauf im selben Konsum-Repo** — der Cross-Repo-Transport (§5) in Norm-Lane + Baseline. Kein generischer Fund → keine Empfehlung. Kein erzwungener Auto-Spawn (§7); der Vermerk steht im Protokoll-Block und der headless-Ausgabe (`retro_recommended`).

## 5. Lernkreis — wie es an `train`/`retro` andockt

Der `security`-Pack bekommt **zwei kollisionsfreie Lanes** (F-030):

| Lane | Hoheit | Regel-IDs | Quelle |
|---|---|---|---|
| **Norm-Lane** | `train` | `security/R<NN>` | externe Standards (OWASP/NIST/RFC), feste `primary_sources` |
| **Einsatz-Lane** | `retro` | `security/E<NN>` | Erfahrung aus echten Läufen (Red-Team-Funde, Review-Muster) |

So schreibt `train` nie in die Erfahrungs-Regeln und `retro` nie in die Norm-Regeln — analog zur A/B-Trennung der
Framework-Packs. Der Red-Team-Lauf **erzeugt** die Lessons, die `retro` in die Einsatz-Lane destilliert — die dann
den nächsten Lauf schärfen.

### Cross-Repo-Transport generischer Funde (Konsum-Repo → zentrale Fabrik)

Der Red-Team-Lauf klassifiziert jeden bestätigten Fund bereits **generisch/universell vs. projekt-spezifisch**
(F-033 Teil C). Ein Lauf findet aber in einem **Konsum-Repo** statt, während die Fabrik-Regeln (Norm-Lane +
Baseline) in **agent-flow** leben. `retro` liest **nur** das cwd-Repo — der Transport der **generischen** Härtungen
in die Fabrik geschieht deshalb über einen **empfohlenen `/retro`-Lauf im selben Konsum-Repo**: Enthält der Lauf
mindestens einen generischen Fund, **empfiehlt** der Red-Team-Agent nach dem Landen seines PRs genau dort eine Retro
(kein erzwungener Auto-Spawn, §7). `retro` promotet die generischen Funde dann in die **Norm-Lane**
(`security/R<NN>`, via `train`) **und** die **Security-Baseline** (`docs/architecture/born-secure-baseline.md`
Teil B) — so schließt sich der Kreis Konsum-Repo → zentrale Fabrik. Der Vermerk ist im Protokoll-Block und der
headless-Ausgabe sichtbar (`retro_recommended`), damit auch ein GUI-/Nachtwächter-Konsument den Folge-Schritt kennt.
Bindend: Spec `docs/specs/factory-learning-improvements.md` AC3.

## 6. Architektur-Aufteilung (zwei Repos)

Wie beim Reconcile: **dünner Auslöser im dev-gui, gesamte Logik in agent-flow.**

- **agent-flow (dies, F-030/F-031; scharf F-032):** Skill `skills/red-team/SKILL.md` + Agent `agents/red-team.md` + Pack-Härtung. Sprach-neutral, headless-konsumierbar (`claude -p`). **Scharfer Betrieb (F-032):** echter, nicht-destruktiver Nuclei-Lauf (frische Templates pro Lauf) **hinter dem Feuer-Freigabe-Gate** — kein Trockenlauf mehr; Ziel-URL wird server-seitig aus dem Allowlist-Eintrag abgeleitet (Spec AC9–AC14).
- **dev-gui (gebaut, F-090):** eine **Red-Team-Kachel** im „Fabrik"-Panel, die — genau wie der Reconcile-Button — nur einen Fabrik-Befehl über einen Headless-Runner startet (`HeadlessRedTeamRunner`). Ziel-Auswahl = Allowlist aus §3 (kein Freitext); leitet die Ziel-**URL** server-seitig aus dem Allowlist-Eintrag ab (VPS-Host:hostPort bzw. öffentliche Hostname). Zeigt Protokoll + verlinkt die erzeugten Board-Items. **Cloudflare-Koordination (§2) ist ein vorab menschlich gesetzter Schritt — die Kachel PRÜFT die Ausnahme, SETZT sie NIE selbst** (Standard-Modus `direkt` braucht keine).

## 7. Bewusst NICHT

- **Kein Auto-Feuern gegen Live-Infra.** Der Lauf ist scharf (echter Nuclei-Lauf, F-032), aber jeder Lauf gegen eine laufende App ist eine **per-Lauf menschlich autorisierte** Aktion (Feuer-Freigabe-Gate) — nie ungefragt/automatisch.
- **Keine automatische Cloudflare-Umkonfiguration.** Die Ausnahme setzt der Mensch **vorab**; der Lauf **prüft** sie nur (Spec AC13). Standard-Modus `direkt` braucht keine.
- **Keine Detection-Evasion / Tarnung** (§2).
- **Keine fremden Ziele** — konstruktiv ausgeschlossen (§3).
- **Kein destruktives Ausnutzen** — die Triage beweist Ausnutzbarkeit, ohne Schaden anzurichten (kein Datenabfluss, keine Löschung).
- **Keine tagesaktuellen CVEs im Pack** — die gehören in die self-updating Scanner-Feeds + Dependabot (§4.3).

## 9. Phase B — Strix gegen Wegwerf-Kopie (F-035)

> **Status:** akzeptiert (Spec `docs/specs/red-team-capability.md` AC15–AC29). Erweitert den Lauf um eine **zweite
> Phase** im **selben** Aufruf — **kein** zweiter Skill/Auslöser, **kein** separates Plugin. Der bestehende Nuclei-Lauf
> (§4.3, AC9–AC14) wird zu **Phase A** und bleibt **HART unverändert**.

### 9.1 Grundkonflikt & Auflösung

Das externe CLI **Strix** (`usestrix/strix`) weist Schwachstellen nicht nur nach, sondern **nutzt sie aktiv aus**
(funktionierende PoC-Exploits). Es hat **keine** eingebaute Ziel-Sperrliste und **keinen** „nur erkennen"-Modus —
Exploitation ist Standardverhalten. Das widerspricht der harten „**kein destruktives Ausnutzen**"-Grenze (§7), **wenn
es gegen die echte Produktions-App liefe**. Auflösung: Strix feuert **nie** gegen Produktion, sondern gegen eine
**wegwerfbare, isolierte lokale Kopie**, auf der aktives Ausnutzen unbedenklich ist.

### 9.2 Zwei-Phasen-Lauf (ein Aufruf)

1. **Phase A (bestehend, unverändert).** Nuclei gegen die echte laufende Produktions-App — nicht-destruktiv, über die
   konstruktive Allowlist (§3), hinter dem Feuer-Freigabe-Gate. Exakt wie §4.3 / Spec AC9–AC14.
2. **Phase B (neu).** Danach automatisch, ohne manuellen Zwischenschritt:
   - **Wegwerf-Kopie hochfahren** — `/agent-flow:preview up` startet das produktive ghcr-Image mit eigener,
     leerer/frisch migrierter Test-DB, eigenem Docker-Network/Volume (`skills/preview/SKILL.md`).
   - **Strix feuern** — gegen `http://localhost:<preview_port>`; dort **darf** es aktiv ausnutzen (keine echten Daten).
     Strix läuft auf einer **fest gepinnten Version** (Konstante, §9.4), zieht seinen **eigenen LLM-API-Key** aus dem
     Secret-Handling (`STRIX_LLM_API_KEY` via `scripts/load-env.sh`) und bekommt ihn nur als Env in den Container.
   - **Aufräumen (garantiert)** — `/agent-flow:preview down`, auch im Fehler-/Timeout-Pfad (Spec AC18).

### 9.3 Berichte — dieselben drei Ausgänge, Quelle-markiert

Beide Phasen fliessen in **dieselben** drei Lernkreis-Ausgänge (§4.5): Protokoll `docs/red-team-audit.md`, Board-Items,
Lessons. **Jeder Fund trägt seine Quelle** (Spec AC24), weil beide unterschiedlich zu werten sind:

| Quelle | Beweislage |
|---|---|
| **Produktion (Nuclei)** | real bestätigt, **nicht** ausgenutzt |
| **Wegwerf-Kopie (Strix)** | **aktiv ausgenutzt/bewiesen**, aber nur lokal — Produktions-Verifikation offen |

Der Protokoll-Block bekommt getrennte Phase-A/Phase-B-Abschnitte (AC25); das headless-JSON ein rückwärtskompatibles
`phase_b`-Objekt (AC26).

### 9.4 Externe Abhängigkeit — gepinnt, bewusst gebumpt

Strix ist ein externes Docker-Image mit eigenem LLM-Call. **Kein** Auto-„immer neueste" (eine neue Version könnte sich
unbemerkt aggressiver verhalten): die Version ist an **einer** Stelle **gepinnt** (Konstante im Subsystem/Skill) und wird
**nur bewusst** über den `/agent-flow:upgrade`-Agenten gebumpt (immer als PR). `docs/architecture/upgrade-subsystem.md`
nennt Strix als gepinnte Tool-Abhängigkeit.

### 9.5 Graceful Skip & Opt-out

Phase B verlangt **Docker** + **`STRIX_LLM_API_KEY`** + ein **preview-fähiges Repo** (Profil + ghcr-Image). Fehlt eines,
oder ist der Lauf repo-los → Phase B wird **sauber übersprungen** (Warn-Zeile + `phase_b: skipped`), Phase A läuft normal
weiter (Spec AC22). Das Skill-Argument `phase_b=aus` deaktiviert Phase B bewusst (AC23). Da Strix eigene LLM-Kosten
verursacht, weist der Lauf **vor** Phase B einen Kosten-Hinweis aus (AC28).

## 8. Touchpoints

- `knowledge/security.md` — zwei Lanes (§5), feste Quellen, 3-Speed-Kopfnote.
- `agents/train.md` — `/train security` respektiert `primary_sources`/`non_sources`.
- `agents/retro.md` — schreibt für den `security`-Domänen-Pack ausschließlich in die Einsatz-Lane (`security/E<NN>`).
- `agents/reviewer.md` — Enforcement der Lane-Trennung.
- `skills/flow/SKILL.md` — Security-Frische-Nudge (§siehe security-pack-freshness).
- `agents/red-team.md`, `skills/red-team/SKILL.md` — die Fähigkeit selbst.
- `docs/red-team-audit.md` (pro Projekt) — Protokoll-Logbuch (Phase A + Phase B, Quelle-markiert — §9.3).
- `skills/preview/SKILL.md` — Phase B fährt die Wegwerf-Kopie hoch/runter (`up`/`down`, §9.2).
- `scripts/load-env.sh` — liefert `STRIX_LLM_API_KEY` (Strix-eigener LLM-Key, maskiert) für Phase B (§9.2).
- `docs/architecture/upgrade-subsystem.md` — Strix als gepinnte, bewusst bumpbare Tool-Abhängigkeit (§9.4).
