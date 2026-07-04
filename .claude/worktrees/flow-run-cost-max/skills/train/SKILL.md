---
name: train
description: Startet den train-Agenten — recherchiert im Netz aktuelle Patterns für eine Sprache, ein Framework oder ein Build-Tool und öffnet einen PR, der den entsprechenden Pack aktualisiert (mit Quellen, PR+Gate). Sondermodus /train model-tiers kuratiert die Modell-Klassen-/Cost-Matrix gegen die Anthropic-Modell-Quellen. Bootstrap-Modus /train --bootstrap <pack-id> [<url> …] legt einen neuen Pack aus mitgegebenen Primärquellen an (from-scratch, kein Vorgänger nötig). Aufruf: /train [--cost <mode>] [--force] [--bootstrap] <pack-id> [<pack-id> … | <url> …]
---

# /train [--cost <mode>] [--force] [--bootstrap] <pack-id> [<pack-id> … | <url> …]

## Token-Parsen (immer zuerst)

Bevor Pack-IDs aufgelöst werden, werden alle Steuer-Token aus der Eingabe herausgeparst:

1. `--cost <mode>` — Cost-Mode-Argument; `<mode>` gehört NICHT zur Pack-ID-Liste.
2. `--force` — Sondermodus-Flag (nur für `model-tiers`); gehört NICHT zur Pack-ID-Liste.
3. `--bootstrap` — Bootstrap-Flag (Pack anlegen statt abbrechen); gehört NICHT zur Pack-ID-Liste.

**Ist `--bootstrap` gesetzt:** Das erste verbleibende Token nach den Flags ist die **Pack-ID** (genau eine). Alle weiteren Token, die mit `http://` oder `https://` beginnen, sind **Quell-URLs** und werden als `primary_sources` an den Bootstrap-Agent übergeben. Quell-URLs gehören NICHT zur Pack-ID-Liste. Verbleiben danach noch Nicht-URL-Token (weder Flag noch URL), ist das ein Aufruf-Fehler → **SOFORTIGER STOPP** mit Meldung:

> `Unbekannte Token nach Pack-ID: '<token> …' — beim --bootstrap-Modus sind nach der Pack-ID nur URLs erlaubt (http:// oder https://). Aufruf: /train --bootstrap <pack-id> [<url> …]`

**Ist `--bootstrap` NICHT gesetzt:** Alles, was nach dem Herausparsen der obigen Tokens übrig bleibt, ist die **Pack-ID-Liste** (ein oder mehrere durch Leerzeichen getrennte IDs).

**Cost-Mode auflösen:** Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced` (Kurzformen `low`/`max`/`front` normalisieren; `front`→`frontier`). Beim Task-Dispatch den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Rolle `train`) mitgeben; bei `balanced` **keinen** Override (Frontmatter `sonnet` gilt).

## Sondermodus-Prüfung (vor der Auflösung)

Enthält die Pack-ID-Liste `model-tiers` oder ist `--bootstrap` gesetzt, und die Liste hat gleichzeitig **≥ 2 Pack-IDs**: **SOFORTIGER STOPP** mit Fehlermeldung:

> `Fehler: Sondermodi (model-tiers, --bootstrap) sind nicht mit einer Mehr-Pack-Liste kombinierbar. Bitte jeden Sondermodus einzeln aufrufen.`

Sondermodi erfordern exakt **eine** Pack-ID.

## Einzel-Pack-Pfad (genau eine Pack-ID in der Liste)

Verhält sich **bitgenau wie bisher** — keine Verhaltensänderung:

Starte den **train**-Agenten (Task-Tool) für eine **Sprache**, ein **Framework** oder ein **Build-Tool**. Pack-ID-Resolver (analog `docs/architecture/framework-build-subsystem.md` §8):

| pack-id Form | Resolver | Beispiel |
|---|---|---|
| `model-tiers` | **Sondermodus (Vorrang):** → `knowledge/model-tiers.md`; Modell-Klassen-/Cost-Matrix-Kuration statt Sprach-/Framework-Wissen | `/train model-tiers`, `/train model-tiers --force` |
| `<id>` | erst `knowledge/<id>.md`, sonst eindeutiges Match in `knowledge/frameworks/` oder `knowledge/build/` | `/train flutter`, `/train maven` |
| `<id>@<major>` | `knowledge/frameworks/<id>-<major>.md` | `/train spring-boot@3` |
| `frameworks/<id>`, `build/<id>` ODER `migration/<id>` | expliziter Pfad-Präfix; löst Ambiguität auf | `/train frameworks/redis@7`, `/train migration/flyway@10` |

**Ambiguität beim Einzel-Aufruf:** Ist `<id>` in 2+ Ordnern vorhanden, **STOPPT** der Agent mit einer Optionsliste — kein Default. Erzwingt explizit-präzise ID (z.B. `frameworks/redis@7`). Dieses harte Stopp-Verhalten gilt **ausschließlich** beim Einzel-Aufruf (genau eine Pack-ID).

**`model-tiers` (Sondermodus — Modell-Klassen-/Cost-Matrix kuratieren):** `/train model-tiers [--force]` hält die Matrix `knowledge/model-tiers.md` (Rolle × `low-cost|balanced|max-quality|frontier` → Modell-Klasse) gegen die **Anthropic-Modell-Primärquellen** (Models overview, Model-Deprecations, Pricing — als `primary_sources` im Pack-Header) aktuell. Greift **nur** bei Klassen-/Tier-Änderungen (neue Klasse/Tier, Deprecation/Umbenennung, Tier-Rebalancing) — **nicht** bei neuen Punktversionen. Setzt bei jedem Lauf `last_curated:` (Frischesignal + Cooldown-State), läuft **monatlich + manuell** (Cooldown, `--force` umgeht), liefert via PR+Gate (kein Auto-/Self-Merge). Bindende Spec: `docs/specs/model-tier-curator.md`; Mechanik: `agents/train.md` Abschnitt „Model-Tiers-Modus".

**`--bootstrap` (Pack anlegen):** `/train --bootstrap <pack-id> [<url> …]` legt einen Pack an, statt abzubrechen. Zwei Pfade je nach Vorgänger-Existenz:

- **Cut-Bootstrap (Vorgänger vorhanden):** Skelett durch Kopie des Vorgänger-Packs (klassischer `/upgrade`-Phase-E-Fall). Quellen werden vom Vorgänger geerbt; mitgegebene URLs erweitern die `primary_sources`. Primär von `/upgrade` (Phase E) genutzt.
- **No-Predecessor-Bootstrap (kein Vorgänger, from-scratch):** Frisches Skelett aus mitgegebenen Quell-URLs. ≥1 URL ist Pflicht — fehlen alle URLs → **STOPP** mit Meldung „Beim From-Scratch-Bootstrap sind ≥1 Quell-URLs als Argument erforderlich (`/train --bootstrap <pack-id> <url> …`)". Existiert der Pack bereits → **STOPP** mit Hinweis „Pack `<id>` existiert — nutze `/train <id>` zum Aktualisieren". Pack-Format (Sprache/Framework/Build/Migration) + Ablageort werden aus der Pack-ID abgeleitet (Spec `docs/specs/train-bootstrap-new-pack.md` V2). 3-Regel-Obergrenze für Sektion A gelockert.

Bei gesetztem `AGENT_FLOW_KNOWLEDGE_DIR` schreibt er zusätzlich in den hermetischen Staging-Dir des Laufs. Vertrag: `docs/specs/train-bootstrap-new-pack.md` (AC1–AC7) + `docs/architecture/upgrade-subsystem.md` §8 + `agents/train.md` Abschnitt „Bootstrap-Modus".

Er liest den vom Resolver bestimmten Pack, recherchiert aus **Primär-/autoritativen Quellen** (offizielle Docs/Specs/Release-Notes — keine Einzel-Blogs; bei Framework-/Build-Packs **strikt** nach `primary_sources`/`non_sources` aus dem Pack-Header), priorisiert **faktische Deltas** (Deprecations/neue stabile APIs/Breaking Changes), promotet **max. 3 Regeln/Lauf** und öffnet einen **PR**.

**Bei Framework-/Build-Packs schreibt der train-Agent ausschließlich in Sektion `## A. Stable API & Deprecations`** (Sektion B ist retro-Hoheit; Sektion C nur mit User-Approval). Verstoß = harter Gate-Fail beim Reviewer.

**Merge erst nach `reviewer`-Check + deinem Approve** (Gate §5).

## Mehr-Pack-Pfad (≥ 2 Pack-IDs in der Liste)

### Schritt 1 — Dedup

Doppelt genannte Pack-IDs werden **vor** der Auflösung dedupliziert. Jede eindeutige Pack-ID kommt exakt einmal in die Auflösungs-Liste.

### Schritt 2 — Pro-Pack-Auflösung

Jede Pack-ID wird **einzeln** über denselben Resolver wie im Einzel-Pfad aufgelöst. Ergebnis je ID:

- **Aufgelöst** → Pack-Pfad vermerkt; ID kommt in die Dispatch-Liste.
- **Unauflösbar** (Pack nicht gefunden) → als Fehler vermerkt; ID kommt in die Übersprungen-Liste mit Grund `nicht gefunden`.
- **Ambig** (ID in 2+ Ordnern vorhanden) → als Fehler vermerkt; ID kommt in die Übersprungen-Liste mit Grund `mehrdeutig: <Optionen>`.

**Kein Abbruch** — eine nicht auflösbare oder ambige ID in der Mehr-Pack-Liste stoppt den Lauf nicht; die übrigen Packs werden weiterverarbeitet.

### Schritt 3 — Paralleler Fan-out

Für jede ID in der Dispatch-Liste wird **ein** `train`-Agent via Task-Tool gestartet. Alle Dispatches erfolgen **in einer einzigen Runde** (echte Parallelität innerhalb der Session):

- Jeder Agent bekommt seinen **einzelnen Pack** + den bereits aufgelösten **Cost-Mode-`model`-Override** (gleicher Wert für alle Agenten; bei `balanced` kein Override — Frontmatter gilt).
- Jeder Agent führt den **regulären Einzel-Pack-Ablauf** aus: Pack lesen → Web-Recherche → max. 3 Regeln → Branch `train/<pack-id>` → eigener PR.
- Es gibt **keinen** Sammel-Agenten, der mehrere Packs nacheinander abarbeitet.

**Kein paketübergreifender PR.** Jeder Agent öffnet seinen eigenen PR auf seinem eigenen Branch. Kein gemeinsamer Sammel-PR, kein paketübergreifender Merge.

**Sonderfall — alle IDs unauflösbar:** kein Dispatch; die Zusammenfassung (Schritt 4) listet alle als übersprungen. Kein Crash.

### Schritt 4 — Sammel-Übersicht ausgeben

Nach Abschluss aller parallelen Agenten gibt die Skill eine **Sammel-Übersicht** aus:

```
Mehr-Pack-Train abgeschlossen
──────────────────────────────
Dispatcht (N Packs):
  ✓ <pack-id-1>  → PR #<nr>: <link>
  ✓ <pack-id-2>  → keine Änderung (PR nicht geöffnet)
  ✗ <pack-id-3>  → Agent-Fehler: <Kurzbeschreibung>

Übersprungen (M IDs):
  ⚠ <pack-id-A>  → nicht gefunden
  ⚠ <pack-id-B>  → mehrdeutig: knowledge/frameworks/redis-7.md ODER knowledge/build/redis — bitte präziser: /train frameworks/redis@7
```

Status-Werte je dispatcht-em Pack:
- **PR geöffnet** — Link zum PR
- **keine Änderung** — Agent fand keine neuen Regeln, kein PR geöffnet
- **Fehler** — Agent hat einen Fehler gemeldet (Kurzbeschreibung)

Die Übersprungen-Liste enthält jede nicht aufgelöste ID mit dem Grund (nicht gefunden / mehrdeutig + Optionsliste).
