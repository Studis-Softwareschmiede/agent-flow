# Reconcile-Subsystem — Doku wieder mit der Realität in Deckung bringen

> **Status:** akzeptiert + **gebaut** (Stufe 1 + Stufe 2, agent-flow-Teil — Stories S-009..S-012).
> **Erweitert 07.07.2026 (Idea-Roundtrip): Stufe 3 (Obsidian-Rückspielung), akzeptiert — noch nicht gebaut** (§3).
> Quer-Achse wie
> `traceability-subsystem.md` / `model-tier-subsystem.md`. Skill `/agent-flow:reconcile` (`skills/reconcile/SKILL.md`).
> Offen (Cross-Repo, SR3): der Auslöser-Button im dev-gui-„Spezifikation"-Reiter (dev-gui Story S-201). Sprach-**neutral**.

## 1. Zweck & Problem

Die `docs/` (Konzept → Architektur → Spec) sind die durable Source of Truth (CONCEPT §4d). In der Praxis
**eilt der Code ihnen voraus** (Direkt-Commits, Bestand vor Adoption, Hotfixes) **und** die Spec-**Form** veraltet,
wenn die Fabrik ihre Vorlage weiterentwickelt. Beide Driften akkumulieren unbemerkt.

Heute decken zwei Mechanismen je nur einen Teil ab; **die wiederkehrende Aufholung fehlt**:

| Mechanismus | Richtung | Wann | Deckt | Lücke |
|---|---|---|---|---|
| **Drift-Gate** (`reviewer`, CONCEPT §4d) | verhindert Code-ohne-Spec | jeder `/flow`-PR | **neue** Drift im Fluss | nur was durch `/flow` läuft |
| **Spec-aus-Code** (`/adopt` §2) | Code→Doc | **einmalig** bei Adoption | initialer Doc-Stand | kein Wiederholungslauf |
| **Reconcile** (dies) | Form + Inhalt | **on-demand** (Button) | akkumulierte Form- + Inhalts-Drift | — |

## 2. Auslöser — dünner Button, Logik in der Fabrik

Ein **Button im „Spezifikation"-Reiter** eines Projekts (dev-gui). Er ist **dünn**: wie die bestehenden
Buttons „Board abarbeiten" (`/agent-flow:flow`) und „Änderung erfassen" (`/agent-flow:requirement`) startet er
einen **Fabrik-Befehl** im Projekt-Terminal — Arbeitstitel **`/agent-flow:reconcile`**. Die gesamte Logik
(Erkennen, Konvertieren, Nachziehen) lebt in **agent-flow**; dev-gui ruft sie nur auf (POST `/api/command`).

## 3. Drei Stufen

### Stufe 1 — Form (läuft IMMER, auch bei vollem Board)
Bringt jede Spec auf die **neueste Vorlagen-Version**. Sicher jederzeit, weil rein doku-intern (kein Code-Bezug).

- **Versions-Stempel.** Jede Spec trägt im Frontmatter `spec_format: <name-version>`. Der Wert ist die
  **offizielle Bezeichnung des Standards** (kein hausgemachter Zähler) — aktuell **`use-case-2.0`** (die
  „Use-Case 2.0"-Methodik, vgl. Ivar Jacobson / Simon Martinelli; siehe §8). Die aktuelle Vorlage
  (`templates/_docs/specs/_template.md`) nennt im Kopf ihre eigene `spec_format`-Version.
- **Revisionen folgen der Standard-Nummer** (`use-case-2.0` → `use-case-2.1` → …) — wir erfinden **keine**
  eigene Revisions-Achse. So bleiben Versionen über die offizielle Nummerierung unterscheidbar.
- **Vergleich + Konvertierung.** Specs mit älterem **oder fehlendem** `spec_format` werden **automatisch** in
  die aktuelle Vorlage umgeschrieben (ein Agent restrukturiert) und neu gestempelt.
- **Freigabe.** Das Ergebnis wird zusammen mit Stufe 2 als **ein PR** zur Freigabe vorgelegt (siehe „Freigabe — immer ein PR" unten) — nichts landet ungesehen.

### Stufe 2 — Inhalt (NUR bei leerem Kanban)
Gleicht den **Inhalt** der Doku gegen den **Code** ab.

- **Vorbedingung (hart):** To Do · In Progress · Blocked · In Review **alle leer**. Erst dann ist alles
  Gewollte gebaut → der Code ist „fertig" und damit **maßgebend**. Bei offenem Board: Stufe 2 wird
  **übersprungen** mit Hinweis „erst Board leerräumen" (Stufe 1 läuft trotzdem). Fehlt das Board-Skelett
  komplett (kein `board.yaml`), ist die Vorbedingung **nicht prüfbar** — Stufe 2 wird ebenfalls konservativ
  **übersprungen** mit eigenem Hinweis („kein Board-Skelett vorhanden, Vorbedingung nicht prüfbar"); kein
  impliziter Inhalts-Abgleich, wenn nicht feststeht, ob noch etwas offen ist (Stufe 1 läuft auch hier trotzdem).
- **Erkennen (abgeleitet).** `reviewer` im Audit-Modus (Bestand, kein Diff, kein Gate) vergleicht beobachtbares
  Verhalten im Code gegen `concept.md` + `architecture.md` + `specs/*.md`. **Drift-Heuristik = identisch zum
  Drift-Gate** (Endpunkte/UI/I-O/Fehler-Statuscodes/Datenfelder/NFR-Limits; reiner Refactor zählt nicht).
- **Nachziehen (automatisch).** Code ist Wahrheit → die Doku wird **automatisch** an den Code angeglichen,
  fehlende Docs werden angelegt. **Kein Einzel-Nachfragen pro Abweichung.**
- **Freigabe.** Alles zusammen mit Stufe 1 als **ein PR** zur Freigabe — der Mensch-Gate ist der finale
  Diff-Blick im PR, nicht eine Entscheidung je Drift.

### Stufe 3 — Obsidian-Rückspielung (NUR wenn `obsidian_source` gesetzt; neu 07.07.2026, noch nicht gebaut)
Schliesst den Kreislauf **Idee → Konzept → Spec → Code → zurück zur Idee**. Läuft nach Stufe 2 und spielt
Änderungen auf **Konzept-Ebene** in den Vault zurück — gestaffelt von unten nach oben: eine reine
Verhaltensänderung endet auf Spec-Ebene (Stufe 2); nur Änderungen mit **konzeptioneller Tragweite**
(neue/geänderte `C-NNN`-Abschnitte in `docs/concept.md`) wandern weiter bis zur Ideennotiz.

- **Vorbedingung:** `profile.obsidian_source` gesetzt + Vault erreichbar. Sonst wird Stufe 3 mit Hinweis
  **übersprungen** (Stufen 1+2 laufen normal — kein Regress für Projekte ohne Vault-Anbindung).
- **Ziel-Zonen (strikt):** nur die im `obsidian-ingest-subsystem.md` §4b definierten Zonen — Frontmatter-
  Sync-Felder + generierter Abschnitt `## Stand aus Konzept (generiert)` der über `idea_id`/`C-NNN`
  verankerten Ideennotiz. Persönliche Ausarbeitung wird **nie** berührt; gelöscht wird **nie**
  (Überholtes → `idea_status: superseded`).
- **Waisen aufwärts** (Konzeptabschnitt/Spec ohne Ideen-Herkunft, typisch nach Code-first): Stufe 3 legt
  eine **neue Ideennotiz** im `obsidian_source`-Ordner an — klar gekennzeichnet als repo-first entstanden
  (`idea_status: adopted`, Herkunft `(← C-NNN)`), Inhalt nur in der generierten Zone.
- **Drei-Wege-Abgleich** über `last_sync`/`sync_hash` je Ideennotiz:
  - nur Repo geändert → Rückspielen in die generierte Zone + Sync-Felder stempeln
  - nur Obsidian geändert → **kein** Overwrite; Kandidat für den nächsten Ingest/`--sync`
    (Autorität der Notiz-Seite bleibt beim `from-notes`-Vertrag)
  - **beide geändert → Konflikt wird dem Menschen vorgelegt, nie automatisch entschieden**
- **Autoritätsmodell (gestaffelt):** innerhalb des Repos bleibt „Code gewinnt" (Stufe 2, unverändert);
  Richtung Vault gewinnt niemand automatisch — die generierte Zone ist Spiegel, die persönliche Zone
  unantastbar, Konflikte entscheidet der Mensch.
- **Freigabe:** Repo-seitige Änderungen laufen wie bisher über den **einen PR**; Vault-seitige Patches
  werden im PR-Text als Liste protokolliert (Notiz + Zone) und erst **nach Merge** des PRs ausgeführt —
  so bleibt der Mensch-Gate auch für den Vault wirksam.

### Freigabe — immer ein PR (unabhängig von `merge_policy`)
Reconcile landet sein **Gesamt-Ergebnis** (Stufe 1 + Stufe 2 + `docs/spec-audit.md`-Block) **immer als genau
einen PR** — auch bei `merge_policy: direct`. Der Reconcile-Diff ist ein **Review-Artefakt**, kein
Direkt-Push-Fall; deshalb entfällt der frühere `direct`-Sonderfall (unstaged Working-Tree-Diff, kein Commit)
für reconcile ersatzlos. Mechanik (identisch zum bisherigen `pr`-Pfad, analog `train`/`retro`): Branch
`reconcile/<YYYY-MM-DD>` ab `default_branch` · **ein** Commit mit allen berührten Dateien + Logbuch-Block ·
Push · `gh pr create` gegen `default_branch` · **kein** Self-Merge (Mensch-Gate). Auth vor dem PR über
`${CLAUDE_PLUGIN_ROOT}/scripts/ensure-gh-auth.sh`.

- **Kein Remote / keine Auth** → kein stiller Fehlschlag: committeter lokaler Branch (bzw. Working-Tree-Diff,
  falls schon das Branchen/Committen scheitert) bleibt erhalten + klare Nachzieh-Meldung.
- **No-Op-Lauf** (weder Stufe 1 noch Stufe 2 hat etwas geändert) → **kein** PR, **kein** Branch; nur der
  `--no-op`-Logbuch-Block wird im Working-Tree geschrieben (Buchhaltung, kein Review-Artefakt). Ein PR entsteht
  ausschließlich bei ≥ 1 substanziell geänderter/angelegter Doku-Datei.

## 4. Logbuch — `docs/spec-audit.md` (ein Dokument pro Projekt)

Pro Lauf **ein knapper Block**: Datum + je eine Zeile pro berührtem Dokument („Spec X auf use-case-2.0
konvertiert" / „Konzept Y nachgezogen"). Neueste oben. **Mehr nicht** — keine Tabelle, keine Begründung,
keine Fundstellen. Es hält die **getroffenen Änderungen** fest (durable Historie), nicht die abgeleitete
Roh-Drift-Liste (die ist ephemer). Liegt im Ziel-Repo neben `docs/`.

## 5. Architektur-Aufteilung (zwei Repos)

| Teil | Repo | Inhalt |
|---|---|---|
| **Button + Anstoßen** | `dev-gui` | Button im „Spezifikation"-Reiter, POST `/api/command` mit `/agent-flow:reconcile` |
| **Abgleich-Logik** | `agent-flow` | Skill `/agent-flow:reconcile` + Agenten (Erkennen via `reviewer`-Audit, Konvertieren/Nachziehen) + `spec_format`-Feld in Vorlage |

## 6. Touchpoints

- **dev-gui** — der Button (Muster wie „Board abarbeiten"/„Änderung erfassen").
- **`/agent-flow:reconcile`** (neu) — orchestriert Stufe 1 + Stufe 2 + Stufe 3; einziger Schreiber der Doc-Änderungen
  (immer als **ein PR**, unabhängig von der Projekt-`merge_policy` — der Reconcile-Diff ist ein Review-Artefakt).
- **`reviewer`** — Audit-Modus liefert die Inhalts-Drift (Stufe 2); setzt **kein** Gate, berichtet nur.
- **`requirement` / konvertierender Agent** — Stufe-1-Umschreibung in die neue Vorlage.
- **`templates/_docs/specs/_template.md`** — bekommt das `spec_format`-Feld + nennt die aktuelle Version;
  `requirement` stempelt neue Specs künftig automatisch.
- **CONCEPT §4d** — definiert die *vorwärtige* Drift-Disziplin; dieses Subsystem ist die *rückwärtige* Aufholung.
- **`obsidian-ingest-subsystem.md`** — Stufe 3 nutzt dessen Vault-Schreibzonen (§4b) und ID-Verankerung
  (`idea_id`/`C-NNN`); der `--audit`-Modus dort liefert die Waisen-aufwärts-Liste als Input.

## 7. Bewusst NICHT

- **Kein Landen ohne Freigabe** — das Gesamt-Ergebnis geht **immer** durch genau einen PR mit Mensch-Gate;
  nichts landet ungesehen, nie per Self-Merge, nie per Direkt-Push (auch nicht bei `merge_policy: direct`).
- **Kein Inhalts-Abgleich (Stufe 2) bei offenem Board** — sonst würde halbfertige Arbeit zur Wahrheit erklärt.
- **Kein eigener interner Revisions-Zähler** — wir folgen der Standard-Version (`use-case-2.x`).
- **Kein per-Drift-Nachfragen in Stufe 2** — Code ist maßgebend, der Mensch prüft das Gesamt-Ergebnis.
- **Kein Blind-Overwrite im Vault (Stufe 3)** — geschrieben wird nur in die definierten Zonen; bei
  beidseitiger Änderung entscheidet immer der Mensch; gelöscht wird nie (`superseded`).
- **Keine handgepflegte Drift-Liste als Wahrheit** — durable ist nur das Logbuch (§4).
- **Kein eigener reconcile-Agent** (Rolle ≠ Expertise): Erkennung = `reviewer`-Audit, Orchestrierung = Skill.

## 8. Begriffsquelle (Use-Case 2.0)

Der `spec_format`-Wert nutzt die **offizielle Methodik-Bezeichnung**, nicht eine hausinterne Zahl:
„**Use-Case 2.0**" (großes U/C, Versionsnummer) ist der etablierte Standard (Ivar Jacobson; von Simon
Martinelli vertreten), die geschriebene Spec heißt dort *system use case specification* mit *basic/alternative
flows*. Quellen: martinelli.ch — „Use-Case 2.0: The Forgotten Practice…" · „Stop Starting with Code: Start
with System Use Cases".
