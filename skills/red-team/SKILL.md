---
name: red-team
description: Startet den red-team-Agenten — testet eine AUTORISIERTE eigene App des Owners (Allowlist „läuft auf eigenem VPS" ∩ „eigenes Org-Repo") mit einem etablierten Scanner, triagiert die Funde agentisch und liefert die drei Ausgänge des Sicherheits-Lernkreises (Protokoll in docs/red-team-audit.md, Board-Items für /flow, retro-lesbare Lessons). Reines Dispatch — die gesamte Angriffs-/Triage-/Auslieferungs-Logik liegt im Agenten (agents/red-team.md, Task-Tool); der Skill ist der dünne Auslöser (Muster reconcile). Kein Freitext-Ziel: die Ziel-Kennung wird gegen die konstruktiv erzwungene Allowlist geprüft, ein Ziel ausserhalb → sofort STOPP (Default deny). Keine Detection-Evasion — Cloudflare-Koordination (Freischalten vor Lauf, Scharfstellen danach) ist ein menschlich bestätigter Schritt, kein stiller Automatismus. Liefert IMMER als EIN PR (kein Self-Merge, kein Auto-Feuern); ohne Remote/Auth committeter lokaler Branch als Fallback. Headless-konsumierbar (claude -p): läuft der Skill nicht-interaktiv, endet er mit genau EINEM maschinenlesbaren End-JSON (Muster from-notes/regression-define). Scharfer Betrieb (F-032): der Agent führt einen ECHTEN, nicht-destruktiven Nuclei-Lauf (frische Templates pro Lauf) HINTER dem Feuer-Freigabe-Gate aus — kein Trockenlauf mehr, aber nie Auto-Feuern. Standard-Modus direkt (gegen den Origin) braucht keine Cloudflare-Änderung; durch-cloudflare/beide setzen eine vorab menschlich gesetzte Ausnahme voraus, die der Lauf nur PRÜFT (nie selbst setzt). Ziel-URL wird server-seitig aus dem Allowlist-Eintrag abgeleitet (kein Client-Freitext). Im Ziel-Projekt-Repo ausführen. Aufruf: /agent-flow:red-team ziel=<app-slug> [modus=direkt|durch-cloudflare|beide] [url=<origin-url>] [url_edge=<public-url>].
---

# /agent-flow:red-team ziel=<app-slug> [modus=direkt|durch-cloudflare|beide] [url=<origin-url>] [url_edge=<public-url>]

cwd = Ziel-Projekt-Repo (das eigene Org-Repo der zu testenden App).

**Werkzeug für autorisiertes Testen EIGENER Infrastruktur.** Getestet werden ausschliesslich eigene,
autorisierte Apps des Owners; die Fähigkeit ist als **Detection-Koordination** ausgelegt, **nicht** als
Detection-Evasion (`docs/architecture/red-team-subsystem.md` §2). Dieser Skill ist **reines Dispatch**: er parst
die Ziel-Kennung + den optionalen Messpunkt-`modus`, erzwingt das **Allowlist-Gate** (Architektur §3) und startet den
**red-team**-Agenten (`agents/red-team.md`, Task-Tool). Er enthält **keine eigene** Angriffs-, Triage- oder
Auslieferungs-Logik — die gesamte Fachlogik (Pack lesen, Scanner steuern, Funde triagieren, die drei Ausgänge
liefern, PR öffnen) liegt im Agenten (Muster `reconcile`: dünner Auslöser, Logik in der Fabrik).

Bindender Rahmen: `docs/architecture/red-team-subsystem.md` (§2 Grundhaltung, §3 Allowlist, §4 Ablauf, §6 Repo-Aufteilung) +
`docs/specs/red-team-capability.md` (AC1–AC14). **Sicherheits-Grenze (Spec „Bewusst NICHT"):** der Betrieb ist
**scharf** (echter, nicht-destruktiver Nuclei-Lauf, F-032/AC9–AC14) — aber **hinter dem Feuer-Freigabe-Gate**, nie
**Auto-Feuern**. Der Skill/Agent ändert **nie** die Cloudflare-Konfiguration (Standard-Modus `direkt` braucht keine);
jeder Lauf gegen eine laufende App bleibt eine per-Lauf menschlich autorisierte Aktion.

## 0. Setup

- **`--cost`-Token** zuerst herausparsen (wie bei den anderen Skills, gehört NICHT zum Eingabe-Vertrag): Präzedenz
  `--cost`-Argument > `profile.cost_mode` > `balanced` (`${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md`). Hat
  `red-team` **keine eigene Zeile** in der Tier-Matrix, läuft der Agent in jedem Modus auf seinem Frontmatter-Wert —
  dann beim Dispatch **kein** `model`-Override mitgeben.
- **Headless-Signal auflösen:** Läuft der Skill nicht-interaktiv (GUI-/`-p`-getrieben, kein interaktiver
  `AskUserQuestion`-Adressat) → **`HEADLESS_JSON=1`**. Aufrufform des Konsumenten:
  `claude -p '/agent-flow:red-team ziel=<app-slug> [modus=…]'`. Dann gilt der **Headless-Ausgabevertrag** unten
  (§5). Interaktiv (Terminal-Direktaufruf) bleibt die menschenlesbare Ausgabe unverändert.
- `.claude/profile.md` lesen → `default_branch`, `merge_policy`. **`merge_policy` verzweigt die Freigabe NICHT** —
  der Lauf landet **immer** als PR (AC7), analog `reconcile`.
- Auth sicherstellen — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-gh-auth.sh"` (immer, da immer ein PR folgt).
  Schlägt das fehl: der Lauf läuft trotzdem; der Fallback greift erst beim PR-Öffnen (committeter lokaler Branch, §4).

## 1. Aufruf-Signatur parsen (AC2)

```
/agent-flow:red-team ziel=<app-slug> [modus=direkt|durch-cloudflare|beide] [url=<origin-url>] [url_edge=<public-url>]
```

- **`ziel=<app-slug>`** ist **Pflicht** und ist eine **Ziel-Kennung** (Slug/Identifikator), **KEIN Freitext-Ziel**
  (keine URL, keine IP, kein Hostname aus freier Eingabe). Fehlt `ziel=` → klarer Abbruch „`ziel=<app-slug>` ist
  Pflicht — eine Ziel-Kennung aus der Allowlist, kein Freitext-Ziel", **kein** Dispatch.
- **`modus=`** ist optional, Default **`direkt`** (gegen den Origin — sicherer Default, braucht **keine**
  Cloudflare-Änderung). Zulässig genau: `direkt`, `durch-cloudflare` (misst, was ein Angreifer real erreicht),
  `beide` (beide Messpunkte + Differenz-Ausweis, §2 der Architektur). Anderer Wert → klarer Abbruch, **kein** Dispatch.
  **Nur** `durch-cloudflare|beide` setzen eine **vorab menschlich gesetzte** Cloudflare-Ausnahme voraus — der Lauf
  **prüft** deren Vorhandensein, **setzt sie NIE** selbst; `direkt` braucht **keine** Cloudflare-Koordination. Der Skill
  **koordiniert**, er **tarnt nicht** (§2, AC4, Spec AC13).
- **`url=<origin-url>`** (+ **`url_edge=<public-url>`** bei `modus=beide`) ist die **aufgelöste Ziel-Adresse** des
  Allowlist-Ziels. **KEIN Client-Freitext:** die dev-gui-Kachel leitet sie **server-seitig aus dem autorisierten
  Allowlist-Eintrag ab** (VPS-Host:hostPort bzw. öffentliche Hostname) und reicht sie durch; der Client sendet **nur**
  `ziel`. So bleibt die konstruktive Allowlist gewahrt — die URL gehört **immer** zum geprüften Ziel. Für einen
  **scharfen** Lauf ist `url=` **Pflicht**; fehlt sie → `status: blocked` (kein Raten, Spec AC12). Im Standalone-CLI
  liefert der (vertrauenswürdige) Owner die zum Ziel gehörende URL.

## 2. Allowlist-Gate — Default deny (AC3, HART)

**Vor** jedem Dispatch. Die zulässigen Ziele sind **konstruktionsbedingt** die Schnittmenge
(`red-team-subsystem.md` §3):

> „läuft als Container auf dem eigenen VPS" **UND** „gehört zu einem eigenen Repo der Org".

- Die `ziel`-Kennung wird gegen **diese zur Laufzeit ermittelte** Schnittmenge geprüft (Docker-Blick des VPS ∩
  Org-Repos) — **nicht** gegen eine handgepflegte Liste und **nie** gegen einen freien String. Die eigentliche
  Auflösung + Prüfung ist Sache des Agenten (er hat den Umgebungs-/Repo-Kontext); der Skill reicht die **Kennung**
  durch und macht die Allowlist-Erzwingung zur **expliziten, nicht verhandelbaren** Vertragsbedingung des Dispatchs.
- **Ziel ausserhalb der Schnittmenge → sofort STOPP** mit klarer Meldung („Ziel `<app-slug>` liegt nicht in der
  Allowlist ‚eigener VPS ∩ eigenes Org-Repo' — Red-Team feuert konstruktiv nie gegen Fremdes. Abbruch."), **kein**
  Dispatch, **kein** Scan. Das ist **Default deny**: im Zweifel (Kennung nicht eindeutig auflösbar) wird
  **abgewiesen**, nicht geraten — dieselbe localhost-/Origin-Denkweise wie `security/R16` beim Admin-Setup.

## 3. Dispatch an den red-team-Agenten

Nur nach bestandenem Allowlist-Gate (§2). Dispatch (Task-Tool) an `agents/red-team.md` mit:

```
ziel: <app-slug>
modus: direkt | durch-cloudflare | beide     (Default direkt)
url: <origin-url>                            (server-seitig aus dem Allowlist-Eintrag abgeleitet, AC12)
url_edge: <public-url>                        (nur bei modus=beide)
headless: <true|false>            (aus HEADLESS_JSON, §0 — der AGENT emittiert dann das End-JSON, §5)
default_branch: <aus profile>
```

Der Agent liest `knowledge/security.md`, steuert den etablierten Scanner (Nuclei/OWASP ZAP; Angriffs-Vorlagen frisch
aus dem offiziellen Feed), triagiert die Roh-Funde **ohne destruktives Ausnutzen** (Ausnutzbarkeit wird belegt, nicht
ausgenutzt — kein Datenabfluss, keine Löschung) und liefert die **drei Ausgänge** (§4 der Architektur):

- **Protokoll** — genau **ein** Block in `docs/red-team-audit.md` (ein Dokument pro Projekt, analog `spec-audit.md`):
  „was versucht / hat gegriffen / wurde abgewehrt" (+ Cloudflare-Differenz bei `modus=beide`). Auch ein **No-Op-Lauf**
  (keine Funde) wird protokolliert (AC5).
- **Board-Items** — jede bestätigte Lücke als To-Do-Item, damit `/flow` sie behebt (finden → beheben → erneut testen).
- **Lessons** — generalisierbare Muster als projekt-lokale, **`retro`-lesbare** Lesson (Format `.claude/lessons/`),
  die `retro` in die Einsatz-Lane `security/E<NN>` heben kann (AC6, §5 der Architektur).

Der Agent besitzt Auth/PR-Auslieferung selbst (§4). Dieser Skill ruft `ensure-gh-auth.sh` in §0 nur vorsorglich auf.

## 4. Freigabe — IMMER ein PR (AC7)

Wie `reconcile`: Protokoll + Board-Items + Lessons landen als **ein** PR zur Freigabe — **kein Self-Merge, kein
Auto-Feuern**, unabhängig von `merge_policy`. Die eigentliche PR-Mechanik liegt im Agenten; der Skill hält den
Vertrag fest:

- **Ohne Remote/Auth (Fallback):** ist kein Remote konfiguriert bzw. die Auth aus §0 fehlgeschlagen, bleibt das
  Ergebnis als **committeter lokaler Branch** erhalten (kein Rollback, kein stiller Datenverlust) — mit klarer
  Meldung *warum* kein PR entstand und *wie der Mensch nachzieht* (Remote setzen / `bash scripts/ensure-gh-auth.sh`
  prüfen, dann `git push` + `gh pr create`).
- **Reiner No-Op** (Lauf lief, keine bestätigten Funde): der Protokoll-Block wird trotzdem geschrieben (AC5); ob
  daraus ein PR entsteht, entscheidet der Agent nach dem `reconcile`-Muster (kein leerer No-Op-PR).

## 5. Headless-Ausgabevertrag (AC2) — genau EIN End-JSON

Läuft der Skill mit **`HEADLESS_JSON=1`** (§0), steht **kein** interaktiver Adressat zur Verfügung — der Aufrufer ist
ein Headless-Runner (`claude -p '/agent-flow:red-team ziel=…'`, `.result` = finale Assistant-Nachricht, Muster
`from-notes` §Headless-Ausgabevertrag / `regression-define`). **Emitter ist der Agent** (genau EINER): weil der
Agent die finale Assistant-Nachricht erzeugt, emittiert **er** das End-JSON (`agents/red-team.md` §Ausgabe) — der
Skill reicht nur das `headless`-Signal durch und emittiert **kein** zweites JSON. Der Lauf endet mit **genau EINEM**
maschinenlesbaren JSON-Objekt als **letzter Ausgabe** — **kein** Fliesstext danach:

```json
{ "status": "done" | "no-op" | "blocked" | "needs-auth",
  "pr": "<url>" | null,
  "findings_count": <int>,
  "audit_block": <bool> }
```

- **`status`**:
  - `done` — Lauf durch, mind. ein Ausgang erzeugt (Board-Items/Lessons), als PR (oder Fallback-Branch) ausgeliefert.
  - `no-op` — Lauf durch, **keine** bestätigten Funde (Protokoll-Block trotzdem geschrieben, `findings_count: 0`).
  - `blocked` — harter **Pre-Scan**-Abbruch: **Allowlist-Gate abgewiesen** (Architektur §3, Ziel ausserhalb der Schnittmenge), **fehlende Feuer-Freigabe/Cloudflare-Bestätigung** (Agent Schritt 3), oder Aufruf-/Signaturfehler; `pr: null`, `audit_block: false`.
  - `needs-auth` — Lauf lief durch, aber **PR-Auslieferung** ohne Remote/Auth → Fallback-Branch (`pr: null`), Mensch zieht nach (§4).
- **`pr`** — PR-URL bei erfolgreicher Auslieferung, sonst `null`.
- **`findings_count`** — Anzahl bestätigter (triagierter) Lücken, die als Board-Items angelegt wurden.
- **`audit_block`** — `true`, wenn dieser Lauf einen Block in `docs/red-team-audit.md` geschrieben hat (immer bei
  durchgelaufenem Scan, auch No-Op; `false` bei `blocked` vor dem Scan).

**Fehlerpfad:** ein echter Aufruf-/Ausführungsfehler darf weiterhin mit exitCode ≠ 0 / Freitext enden — **kein**
künstliches Status-JSON über einen echten Fehler legen. Der JSON-Vertrag gilt für **reguläre** Lauf-Enden
(inkl. `blocked` durch das Allowlist-Gate — das ist ein **definiertes** Ergebnis, kein Absturz). Ohne `HEADLESS_JSON`:
menschenlesbare Ausgabe, unverändert.

## Output (interaktiv)

```
Ziel: <app-slug> (Allowlist: <bestanden|ABGEWIESEN — Default deny>)
Modus: <durch-cloudflare | direkt | beide>
Funde: <N> bestätigt (Board-Items angelegt) | keine Funde (No-Op)
Protokoll: docs/red-team-audit.md (1 Block: was versucht / hat gegriffen / wurde abgewehrt<, + Cloudflare-Differenz>)
Lessons: <M> projekt-lokale Lesson(s) für retro (Einsatz-Lane security/E<NN>) | keine
Freigabe: <PR-Link | "Kein PR — Fallback: committeter lokaler Branch (Grund: <kein Remote|Auth fehlgeschlagen>; Nachziehen: …)">
```

## Grenzen (HART)

- **Reines Dispatch** — keine eigene Angriffs-/Scanner-/Triage-/PR-Logik; die liegt im Agenten (`agents/red-team.md`).
- **Kein Freitext-Ziel** (AC3) — nur eine Ziel-**Kennung** gegen die Allowlist „eigener VPS ∩ eigenes Org-Repo";
  Ziel ausserhalb → sofort STOPP, Default deny. Konstruktiv nie gegen Fremdes.
- **Keine Detection-Evasion / Tarnung** (§2) — nur Koordination; die Cloudflare-Freischaltung ist ein **menschlich
  bestätigter** Vor-/Nach-Schritt, kein stiller Automatismus.
- **Kein destruktives Ausnutzen** — die Triage belegt Ausnutzbarkeit, ohne Schaden (kein Datenabfluss, keine Löschung).
- **Kein Self-Merge, kein Auto-Feuern** (AC7) — immer ein PR zur menschlichen Freigabe (Fallback: committeter Branch).
- **Scharfer Nuclei-Lauf ist gebaut (F-032, Spec AC9–AC14)** — der Agent feuert echt (nicht-destruktiv, frische Templates)
  **hinter dem Feuer-Freigabe-Gate**; kein Trockenlauf mehr. `direkt` (Origin) ist der Cloudflare-freie Default.
- **Keine automatische Cloudflare-Umkonfiguration (AC13)** — `durch-cloudflare|beide` setzen eine **vorab menschlich
  gesetzte** Ausnahme voraus; der Lauf **prüft** sie, **setzt sie nie** selbst.
- **Kein** Board-**Status**-Schreiben — Items entstehen als **To Do** (Hoheit `/flow`).
