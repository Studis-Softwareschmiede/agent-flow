---
id: model-tier-curator
title: Model-Tier-Curator (/train model-tiers)
status: draft
version: 1
---

# Spec: Model-Tier-Curator  (`model-tier-curator`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Subsystem, das dieser Curator pflegt, ist in `docs/architecture/model-tier-subsystem.md` spezifiziert (bindend). Die zu pflegende Matrix ist `knowledge/model-tiers.md` (Single Source of Truth). Diese Spec beschreibt **Baustein 3**: den Kurator-Sondermodus, der diese Matrix gegen autoritative Anthropic-Primärquellen aktuell hält. Bausteine 1+2 (Matrix + Skill-Override-Mechanik) existieren bereits (gemergt via #90/#91/#92) und sind **nicht** Gegenstand dieser Spec.

## Zweck

Ein **Sondermodus `/train model-tiers`** im bestehenden `train`-Agenten (`agents/train.md`) hält das Rolle×Modus→Modell-**Klassen**-Mapping in `knowledge/model-tiers.md` aktuell: er recherchiert die offiziellen Anthropic-Modell-Quellen, prüft den Ist-Stand der Matrix dagegen und schlägt **als PR** Korrekturen vor, wenn sich Modell-**Klassen** oder deren Tier-Einordnung autoritativ geändert haben. Der Modus läuft **selten und bewusst** (monatlich + manuell, kein per-Push) und setzt bei jedem Lauf ein **Frischesignal** (`last_curated:`), auch ohne inhaltliche Änderung.

## Kontext / Designnuancen (bindend)

- **Abo, nicht API (dev-gui ADR-001).** Die Engine läuft über das Claude-**Abo**, es entstehen **keine Dollar-API-Kosten**. Der Cost-Mode ist ein **Token-/Modell-Hebel** gegen das Abo-**Kontingent** (5h-/Wochen-Fenster), kein Dollar-Optimierer. → Der Kurator pflegt primär **gültige Modell-Klassen/IDs** (gegen Deprecations) und die **relative Tier-Einordnung**. **Dollar-Preise sind nur informativ**, nie der Optimierungs-Zielwert.
- **Klassen, nicht versionierte IDs.** Die Matrix arbeitet bewusst mit **Modell-Klassen** (`haiku`/`sonnet`/`opus`), nicht mit versionierten IDs (z.B. nicht `claude-sonnet-4-5-20250929`). Das ist robust gegen Punkt-/Versionswechsel. Der Kurator greift **nur bei Klassen-/Tier-Änderungen** ein, **nicht** bei jeder neuen Punktversion einer bestehenden Klasse.
- **Konsistenz mit der Sonar-/retro-Linie.** Cadence = monatlich + manuell, kein per-Push (analog `/retro --sonar` und `/train security`). Cooldown-Gitter analog retro-G3, persistiert über das Frischesignal.
- **PR + Gate wie der bestehende train-Agent.** NIE den Plugin-Cache editieren, PR gegen das agent-flow-Source-Repo, `reviewer`-Check + Mensch-Approve, **NIE Self-Merge**.

## Verhalten

### V1 — Modus-Erkennung
`/train model-tiers` wird vom `train`-Agenten als **Sondermodus** erkannt (Pack-ID `model-tiers` → Ziel-Datei `knowledge/model-tiers.md`). Der Modus weicht vom Normal-/Framework-Pack-Lauf ab: kein Sprach-/Framework-Wissen, sondern Modell-Klassen-Kuration aus den unten verankerten `primary_sources`. Optionales Flag `--force` umgeht den Cooldown (analog `/retro --force`).

### V2 — Quellen-Disziplin (autoritative Primärquellen)
Recherche (WebSearch/WebFetch) **ausschließlich** aus den **autoritativen Anthropic-Primärquellen**:
1. Offizielle **Modell-Übersicht** (docs.claude.com — *Models overview*).
2. **Model-Deprecations-/Lifecycle**-Seite (docs.claude.com).
3. **Pricing**-Seite (anthropic.com / docs.claude.com) — **nur informativ** für die relative Tier-Einordnung, nie als Dollar-Zielwert.

Diese drei Quellen werden als `primary_sources` im **Pack-Header** von `knowledge/model-tiers.md` verankert (analog zur primary_sources-Disziplin der Framework-Packs). Treffer außerhalb der `primary_sources` (Blogs, Foren, Drittanbieter-Tabellen) werden **ignoriert** und nie als Beleg zitiert.

### V3 — Soll-Ist-Abgleich + Änderungs-Trigger
Der Kurator vergleicht den Ist-Stand der Matrix (`knowledge/model-tiers.md`) mit den Primärquellen und schlägt ein Update **nur** bei einem der folgenden **Klassen-/Tier-Trigger** vor:
- **(a) Neue Modell-Klasse / neues Tier** — eine neue Leistungs-/Preis-Klasse **neben** `haiku`/`sonnet`/`opus` ist autoritativ verfügbar → betrifft Matrix-Spalten-Vokabular und Rollen-Einordnung.
- **(b) Deprecation / Umbenennung** einer Klasse — eine in der Matrix verwendete Klasse ist abgekündigt oder umbenannt → Ersatz-Klasse vorschlagen.
- **(c) Tier-Rebalancing** — die Preis-/Leistungs-**Relation** der Klassen hat sich autoritativ verschoben, sodass eine Rollen-Einordnung nicht mehr passt → begründeter Re-Mapping-Vorschlag.

**Kein Trigger:** eine neue **Punktversion** einer bestehenden Klasse (z.B. ein neues `sonnet`-Datum) löst **keine** Matrix-Änderung aus (V Klassen, nicht IDs).

### V4 — Frischesignal (immer)
Bei **jedem** Lauf (auch ohne inhaltliche Matrix-Änderung) setzt der Kurator `last_curated: <heute>` (ISO-Datum) oben in `knowledge/model-tiers.md` — analog zum `last_trained:`-Muster bei `/train security`. Das Frischesignal ist zugleich der Cooldown-Persistenzpunkt (V5).

### V5 — Cadence / Cooldown (monatlich + manuell)
- **Frequenz:** monatlich + manueller Trigger; **kein** per-Push-Lauf.
- **Cooldown-Gitter (analog retro-G3, HART):** maximal **1× pro Kalendermonat** außer `--force`. Vor dem Vorbereiten der Promotion prüft der Kurator das aktuelle `last_curated:`-Datum: liegt es **< 1 Monat** zurück und ist `--force` **nicht** gesetzt → **STOPP** mit Hinweis „Cooldown aktiv bis <datum>, manueller Re-Trigger via `/train model-tiers --force`". Persistenz ausschließlich über `last_curated:` in `knowledge/model-tiers.md` (kein zweiter State-Ort).
- **Default-Entscheid:** Intervall = **monatlich** (gewählt, weil Anthropic Modell-Releases häufiger als quartalsweise erfolgen und die Klassen-Kuration billig ist; konsistent mit der „monatlich + manuell"-Linie der Anforderung). Quartalsweise wurde **nicht** gewählt.

### V6 — PR + Gate (wie bestehender train-Agent)
- Änderung **nie** im read-only Plugin-Cache (`${CLAUDE_PLUGIN_ROOT}`) — der dient nur als Lese-/Dedup-Basis.
- Source klonen, Branch `train/model-tiers`, Änderung in `knowledge/model-tiers.md` (+ `last_curated:`), **LEARNINGS.md**-Zeile (`Proposed`), Commit mit `Co-Authored-By`-Zeile.
- `gh pr create --base main` mit Body = Trigger-Befund + zitierte Primärquellen-Links.
- **Gate:** `reviewer`-Check + **Mensch-Approve** → merge. **NIE** auf `main` pushen, **NIE** den eigenen PR mergen.
- **Reiner Frischelauf** (kein V3-Trigger, nur `last_curated:`-Datum geändert): ebenfalls als PR (durable + Gate), Body „nur Frischesignal, keine Klassen-/Tier-Änderung".

### V7 — Auto-Merge ausgeschlossen
Neue Tiers/Klassen werden **niemals automatisch** in die Matrix übernommen. Jede Matrix-Änderung läuft **ausschließlich als PR-Vorschlag** durch das Gate (V6). **Default-Entscheid:** PR-Vorschlag statt Auto-Übernahme (gewählt, weil eine neue Klasse Rollen-Einordnungs-Urteil braucht und das Subsystem keinen Self-Merge-Pfad kennt — konsistent mit train/retro). Ein Auto-Übernahme-Pfad wurde **nicht** gewählt.

## Acceptance-Kriterien

- **AC1** — `/train model-tiers` wird als Sondermodus erkannt und löst auf die Ziel-Datei `knowledge/model-tiers.md` auf (nicht auf einen Sprach-/Framework-Pack). Der Modus ist in `agents/train.md` dokumentiert. *(V1)*
- **AC2** — Der Modus recherchiert **ausschließlich** aus den drei verankerten Anthropic-Primärquellen (Models overview, Deprecations/Lifecycle, Pricing); diese sind als `primary_sources` im Header von `knowledge/model-tiers.md` hinterlegt. Quellen außerhalb davon werden nicht zitiert. *(V2)*
- **AC3** — Ein Matrix-Änderungsvorschlag entsteht **genau dann**, wenn mindestens einer der Trigger (a) neue Klasse/Tier, (b) Deprecation/Umbenennung, (c) Tier-Rebalancing zutrifft. *(V3)*
- **AC4** — Eine neue **Punktversion** einer bestehenden Klasse löst **keine** Matrix-Änderung aus (Mapping arbeitet auf Klassen, nicht IDs). *(V3)*
- **AC5** — Bei jedem Lauf wird `last_curated: <heute>` (ISO) oben in `knowledge/model-tiers.md` gesetzt — auch wenn kein V3-Trigger zutrifft. *(V4)*
- **AC6** — Cooldown: liegt `last_curated:` < 1 Monat zurück und `--force` ist nicht gesetzt → der Lauf STOPPT mit Hinweis auf das Freigabedatum und `--force`. Mit `--force` läuft er trotzdem. Der Cooldown-State wird ausschließlich aus `last_curated:` gelesen. *(V5)*
- **AC7** — Jede Matrix-Änderung geht als PR (Branch `train/model-tiers`, `--base main`) gegen das agent-flow-Source-Repo; der Plugin-Cache wird nie editiert; der PR-Body nennt den Trigger und zitiert die Primärquellen-Links. *(V6)*
- **AC8** — Der Modus mergt seinen eigenen PR **nicht** und pusht **nie** auf `main`; Merge erst nach `reviewer`-Check + Mensch-Approve. *(V6, V7)*
- **AC9** — Auch ein reiner Frischelauf (nur `last_curated:` geändert, kein Klassen-/Tier-Delta) erzeugt einen PR durchs Gate, gekennzeichnet als reines Frischesignal. *(V6)*
- **AC10** — Es existiert **kein** Auto-Übernahme-Pfad: neue Tiers/Klassen werden ausschließlich als PR-Vorschlag eingebracht. *(V7)*
- **AC11** — Wird ein Klassifikations-Befund des Reviewers in einem Re-Push widerlegt (z.B. „deprecated" vs. „removed", Klasse stable vs. preview), gilt die bestehende `coder/R02`-Verbatim-Pflicht (wörtliches Zitat + exakter Anchor-Link aus der Primärquelle, sonst Klärungs-Comment statt Re-Push). *(Konsistenz mit agents/train.md)*

## Verträge

- **Trigger-Aufruf:** `/train model-tiers [--force]`. `--force` umgeht den Cooldown (V5).
- **Ziel-Datei:** `knowledge/model-tiers.md` (Single Source of Truth der Matrix; bindendes Subsystem-Doc: `docs/architecture/model-tier-subsystem.md`).
- **Pack-Header-Felder** (in `knowledge/model-tiers.md`):
  - `last_curated: <ISO-Datum>` — Frischesignal + Cooldown-State (V4/V5).
  - `primary_sources:` — Liste der drei autoritativen Anthropic-Quellen-URLs (V2).
  - (optional, analog Framework-Packs) `non_sources:` — explizit ausgeschlossene Quellklassen.
- **PR-Vertrag:** Branch `train/model-tiers`, `gh pr create --base main`; Body enthält Trigger-Befund + Quell-Links; LEARNINGS.md-Zeile (`Proposed`).
- **Matrix-Invarianten (vom Subsystem-Doc, bleiben gewahrt):** I1 (`balanced`-Spalte == Agent-Frontmatter), I2 (`low-cost ≤ balanced ≤ max-quality` in der Klassen-Ordnung), I3 (jede dispatchbare Rolle hat eine Zeile). Ein Kurator-Vorschlag, der eine Invariante verletzen würde, muss die Verletzung im PR-Body explizit ausweisen (Reviewer-Gate fängt sie sonst als harten Befund).

## Edge-Cases & Fehlerverhalten

- **Cooldown aktiv, kein `--force`:** STOPP, kein PR, Hinweis mit Freigabedatum (AC6).
- **Primärquelle nicht abrufbar** (Paywall/JS-Render/CDN-Block): Spot-Check-Kommando + Output-Snippet wie bei `coder/R02`; lässt sich der Befund nicht belegen → kein spekulativer Matrix-Eintrag, sondern Klärungs-/Hinweis-Comment.
- **Kein V3-Trigger gefunden:** reiner Frischelauf — nur `last_curated:` aktualisieren, PR als reines Frischesignal (AC9). Kein „Füllmaterial" erfinden.
- **Neue Punktversion einer Klasse:** ignorieren (AC4) — keine Matrix-Änderung, `last_curated:` trotzdem aktualisieren.
- **Invarianten-Konflikt (I1/I2/I3):** Vorschlag darf nicht still die Invariante brechen; entweder konformer Vorschlag oder expliziter Ausweis im PR-Body (Verträge).

## NFRs

- **Token-/Limit-schonend:** seltener Lauf (monatlich + manuell), kein per-Push — schützt das Abo-Kontingent (Cost-Mode-Motivation).
- **Quellen-Integrität:** nur Primärquellen; keine halluzinierten Klassen-Namen/IDs. Klassifikations-Behauptungen belegt (`coder/R02`).
- **Robustheit gegen Versionsrauschen:** Klassen-Granularität statt ID-Granularität (kein Lauf-Anlass bei Punktversionen).

## Nicht-Ziele

- Bausteine 1+2 (Matrix-Datei selbst + Override-Mechanik in `/flow`/`/requirement`/`/retro`/`/train`) — existieren bereits, nicht Gegenstand.
- **Dollar-Kosten-Optimierung** — Preise sind nur informativ (ADR-001: Abo, keine API-Kosten).
- **Versionierte Modell-IDs in der Matrix** — bewusst Klassen-granular.
- **Automatische Matrix-Übernahme / Self-Merge** — ausgeschlossen (V7/AC10).
- **Automatische Modus-/Cost-Wahl anhand Telemetrie** — out of scope des Subsystems.

## Abhängigkeiten

- `docs/architecture/model-tier-subsystem.md` — bindendes Detailkonzept des Subsystems (Invarianten I1–I3, Modi, Override-Mechanik).
- `knowledge/model-tiers.md` — die zu pflegende Single Source of Truth (Ziel-Datei).
- `agents/train.md` — der Agent, in dem der Sondermodus implementiert wird (PR+Gate-Mechanik, `coder/R02`-Verbatim-Pflicht, `--force`-Muster analog retro).
- Konsistenz-Referenzen (Cadence-Linie): `agents/retro.md` (G3-Cooldown), `knowledge/security.md` (`last_trained:`-Muster).
