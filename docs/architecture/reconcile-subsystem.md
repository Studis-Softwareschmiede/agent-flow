# Reconcile-Subsystem — Doku wieder mit der Realität in Deckung bringen

> **Status:** akzeptiert + **gebaut** (Stufe 1 + Stufe 2, agent-flow-Teil — Stories S-009..S-012). Quer-Achse wie
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

## 3. Zwei Stufen

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
- **Freigabe.** Das Ergebnis wird als **ein** Diff zur Freigabe vorgelegt — nichts landet ungesehen.

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
- **Freigabe.** Alles als **ein** Diff zur Freigabe — der Mensch-Gate ist der finale Diff-Blick, nicht eine
  Entscheidung je Drift.

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
- **`/agent-flow:reconcile`** (neu) — orchestriert Stufe 1 + Stufe 2; einziger Schreiber der Doc-Änderungen
  (als PR/Diff je Projekt-`merge_policy`).
- **`reviewer`** — Audit-Modus liefert die Inhalts-Drift (Stufe 2); setzt **kein** Gate, berichtet nur.
- **`requirement` / konvertierender Agent** — Stufe-1-Umschreibung in die neue Vorlage.
- **`templates/_docs/specs/_template.md`** — bekommt das `spec_format`-Feld + nennt die aktuelle Version;
  `requirement` stempelt neue Specs künftig automatisch.
- **CONCEPT §4d** — definiert die *vorwärtige* Drift-Disziplin; dieses Subsystem ist die *rückwärtige* Aufholung.

## 7. Bewusst NICHT

- **Kein Landen ohne Diff-Freigabe** — beide Stufen legen genau einen Diff vor; nichts landet ungesehen.
- **Kein Inhalts-Abgleich (Stufe 2) bei offenem Board** — sonst würde halbfertige Arbeit zur Wahrheit erklärt.
- **Kein eigener interner Revisions-Zähler** — wir folgen der Standard-Version (`use-case-2.x`).
- **Kein per-Drift-Nachfragen in Stufe 2** — Code ist maßgebend, der Mensch prüft das Gesamt-Ergebnis.
- **Keine handgepflegte Drift-Liste als Wahrheit** — durable ist nur das Logbuch (§4).
- **Kein eigener reconcile-Agent** (Rolle ≠ Expertise): Erkennung = `reviewer`-Audit, Orchestrierung = Skill.

## 8. Begriffsquelle (Use-Case 2.0)

Der `spec_format`-Wert nutzt die **offizielle Methodik-Bezeichnung**, nicht eine hausinterne Zahl:
„**Use-Case 2.0**" (großes U/C, Versionsnummer) ist der etablierte Standard (Ivar Jacobson; von Simon
Martinelli vertreten), die geschriebene Spec heißt dort *system use case specification* mit *basic/alternative
flows*. Quellen: martinelli.ch — „Use-Case 2.0: The Forgotten Practice…" · „Stop Starting with Code: Start
with System Use Cases".
