---
id: board-schema
title: Board-Dateiformat — Feature/Story-YAML + board.yaml + Integritätsregeln
status: active
version: 1
---

# Spec: Board-Dateiformat  (`board-schema`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Board-Subsystem ist in `docs/architecture/board-subsystem.md` spezifiziert (bindend, §3–§6). Diese Spec nagelt das **Dateiformat** der git-versionierten Board-Quelle fest: das YAML je Feature/Story, die `board.yaml`-Meta-Datei (ID-Zähler + `schema_version`) und die **Integritätsregeln**, die `board lint` ([[board-cli]]) prüft. Sie ist das Fundament: alle anderen Board-Capabilities lesen/schreiben gegen dieses Schema.

## Zweck

Festlegen, wie ein Board als git-Dateien aussieht — ein menschenlesbares, diff-freundliches YAML pro Feature/Story plus eine `board.yaml`-Meta-Datei — so dass es projektweit eindeutige IDs vergibt, validierbar ist und Merge-Konflikte minimiert. Dieses Schema ist die einzige Wahrheit (keine zentrale DB); git ist das Audit-Log.

## Kontext / Designnuancen (bindend)

- **Source of Truth = Dateien.** Quelle der Wahrheit sind `board/board.yaml`, `board/features/F-###-*.yaml`, `board/stories/S-###-*.yaml` im jeweiligen Repo. Keine zentrale DB (board-subsystem §1/§6).
- **Ein YAML pro Item.** Genau eine Datei je Feature/Story (nicht eine grosse Datei) → minimale git-Merge-Konflikte, ein Item = ein Diff, ein Review (§6).
- **Slug im Dateinamen, ID im Body.** Der Dateiname (`S-014-ionos-adapter.yaml`) dient der Auffindbarkeit; die stabile Referenz ist die `id` im Datei-Body (§6).
- **ID-Vergabe über Zähler.** `board.yaml` hält je Typ einen monoton steigenden Zähler; das CLI vergibt daraus kollisionsfreie `F-`/`S-`-Nummern (§6, §11). Die Vergabe selbst ist Sache von [[board-cli]] — diese Spec definiert nur das Feld + die Eindeutigkeitsregel.
- **Attribute exakt wie §4.1/§4.2.** Pflicht-/Optional-/abgeleitete Felder folgen board-subsystem §4.1 (Feature) und §4.2 (Story); abgeleitete Felder (`stories`, `progress` beim Feature) werden NICHT von Hand gepflegt.
- **Dispo-Felder = Sicht.** `dispo_act`/`tok` spiegeln die Ledger (`items.jsonl`); SoT der Ist-Werte bleibt das Ledger (§4.4, [[metrics-ledger]]). Annahme (konservativ): die Story-YAML hält diese Felder als lesbare Kopie; ein Konflikt Ledger↔YAML ist kein `lint`-Fehler (nur Warnung), da der Join per ID zur Render-Zeit Vorrang hat.
- **AC bleiben in `docs/specs/`.** Akzeptanzkriterien wandern NICHT ins Board; die Story referenziert sie über `spec` + `implements` (§8). `lint` prüft nur, dass die referenzierten AC-Nummern in der Spec existieren — es definiert sie nicht.

## Verhalten

### V1 — `board.yaml` (Board-Meta)
`board/board.yaml` enthält: `schema_version` (int, für spätere Migrationen), `project_slug` (string), und je Typ einen ID-Zähler (`next_feature_id`, `next_story_id` — die zuletzt vergebene bzw. nächste freie Nummer). Fehlt `board.yaml`, gilt das Board als nicht initialisiert.

### V2 — Feature-YAML
`board/features/F-###-<slug>.yaml` trägt die Felder aus board-subsystem §4.1: **Pflicht** `id` (`F-###`), `title`, `goal`, `status` (`Backlog|Planned|Active|Done|Archived`), `priority` (`P0|P1|P2|P3`), `created_at`, `updated_at`. **Optional** `spec`, `definition_of_done`, `labels[]`, `depends[]` (Feature-IDs), `owner`. **Abgeleitet (nicht von Hand)** `stories[]`, `progress`.

### V3 — Story-YAML
`board/stories/S-###-<slug>.yaml` trägt die Felder aus board-subsystem §4.2: **Pflicht** `id` (`S-###`), `parent` (genau eine `F-###`), `title`, `status` (`To Do|In Progress|Blocked|In Review|Done|Verworfen`), `priority` (`P0|P1|P2|P3`), `spec`, `implements[]` (AC-Nummern), `created_at`, `updated_at`. **Optional** `depends[]` (Story-IDs), `labels[]`, `size_est`, `dispo_est`, `dispo_act`, `dispo_forecast`, `estimate_note`, `confidence`, `tok_est`, `branch`, `pr`, `blocked_reason`, `done_at`. `tok_est` (Ganzzahl | null, erwartete Gesamt-Tokens des Flow-Durchlaufs — A-priori-Wert aus `baseline.json`-Lookup bzw. `estimator`, Persistenz als Text via `board set` analog `dispo_est`; s. [[apriori-token-estimate]] AC1/AC2) ist rückwärtskompatibel: fehlt es (Alt-Story), bleibt die Story gültig (kein `lint`-Fehler). Der Status `Verworfen` (Won't-Do/Obsolete) ist **terminal** wie `Done`, aber nicht *erfolgreich* — Semantik + terminale Wertung in `next`/`rollup`/`/flow` siehe [[story-status-verworfen]].

**Sonderfall: importierte Stories** (Feld `github_issue` gesetzt): `spec` und `implements` dürfen bei einem GitHub-Export-Lauf fehlen/null sein, wenn kein `Spec:`/`implements:`-Marker im Issue-Body vorhanden war. `lint` meldet fehlende Werte dieser beiden Felder dann als **WARN STORY-UNSPEC** (nicht als FEHLER FIELD-REQUIRED). Der Owner zieht sie im Cut-PR nach (Drift-Gate greift zur Implementierungszeit via coder/reviewer). Native Stories (ohne `github_issue`) behalten `spec`/`implements` als harte Pflichtfelder (FIELD-REQUIRED bei Fehlen).

### V4 — Enum- & Typ-Konformität
Jedes Enum-Feld trägt ausschliesslich einen der in V2/V3 erlaubten Werte; IDs entsprechen den Mustern `^F-\d{3,}$` / `^S-\d{3,}$`; `implements[]` sind AC-Tokens (`AC<n>`); Zeitstempel sind ISO-8601-UTC. Abweichungen sind `lint`-Fehler.

### V5 — `lint`-Regel: IDs eindeutig
Keine zwei Features teilen sich eine `id`; keine zwei Stories teilen sich eine `id`. Der Dateiname-Präfix (`F-###`/`S-###`) muss zur `id` im Body passen. Verstoss → `lint`-Fehler (deckt das Doppel-ID-Risiko aus §11 ab).

### V6 — `lint`-Regel: parent existiert
Jede Story hat genau ein `parent`; das referenzierte Feature existiert als Datei. Fehlendes/leeres/unbekanntes `parent` → `lint`-Fehler.

### V7 — `lint`-Regel: depends auflösbar
Jede `depends`-Referenz (Story→Story, Feature→Feature) zeigt auf eine existierende Datei desselben Typs. Story-`depends` dürfen NICHT auf Features zeigen und umgekehrt. Eine Selbst-Referenz oder ein Zyklus in `depends` → `lint`-Fehler. Unauflösbare Referenz → `lint`-Fehler.

### V8 — `lint`-Regel: AC in Spec
Für jede Story muss die in `spec` genannte Datei existieren und jede in `implements[]` genannte AC-Nummer als `AC<n>` darin vorkommen. Fehlende Spec-Datei oder unbekannte AC-Nummer → `lint`-Fehler (Drift-Gate-Bindung, §8).

### V9 — `lint`-Regel: Pflichtfelder & Enums
Fehlt ein Pflichtfeld (V2/V3) oder verletzt ein Feld die Typ-/Enum-Konformität (V4) → `lint`-Fehler mit Datei + Feldname.

### V10 — `lint`-Regel: abgeleitete Felder konsistent
`stories[]`/`progress` eines Features müssen den tatsächlichen Kind-Stories entsprechen (jede Story mit `parent=F` ist in `F.stories[]`; `progress` zählt die Kind-Status korrekt). Inkonsistenz → `lint`-**Warnung** (nicht Fehler), da `board rollup` ([[board-cli]]) sie neu berechnet.

### V11 — Determinismus & Fehlerausgabe
`board lint` ist deterministisch (gleiche Dateien → gleiches Ergebnis), gibt je Verstoss eine Zeile `FEHLER|WARN <regel-id> <datei> <feld/detail>` aus und endet mit Exit-Code ≠ 0 bei mindestens einem Fehler, 0 bei nur Warnungen/grün.

## Acceptance-Kriterien

- **AC1** — `board/board.yaml` enthält `schema_version` (int), `project_slug` und je einen ID-Zähler `next_feature_id`/`next_story_id`; ohne `board.yaml` gilt das Board als nicht initialisiert. *(V1)*
- **AC2** — Feature-YAML trägt alle Pflichtfelder aus board-subsystem §4.1 (`id,title,goal,status,priority,created_at,updated_at`) plus die optionalen/abgeleiteten Felder; `status`∈{Backlog,Planned,Active,Done,Archived}, `priority`∈{P0,P1,P2,P3}. *(V2)*
- **AC3** — Story-YAML trägt alle Pflichtfelder aus board-subsystem §4.2 (`id,parent,title,status,priority,spec,implements,created_at,updated_at`) plus die optionalen Felder; `status`∈{To Do,In Progress,Blocked,In Review,Done,Verworfen}, `priority`∈{P0,P1,P2,P3}. `Verworfen` ist ein terminaler Status (Won't-Do/Obsolete, [[story-status-verworfen]]). Für **importierte Stories** (`github_issue` gesetzt) sind `spec`/`implements` bei Fehlen WARN STORY-UNSPEC (kein FEHLER), bis der Owner sie im Cut-PR nachzieht. *(V3)*
- **AC4** — IDs matchen `^F-\d{3,}$`/`^S-\d{3,}$`, Enums tragen nur erlaubte Werte, `implements[]` sind `AC<n>`-Tokens, Zeitstempel ISO-8601-UTC; Abweichung → `lint`-Fehler. *(V4, V9)*
- **AC5** — `lint` meldet doppelte Feature-/Story-IDs und einen Dateiname-Präfix, der nicht zur `id` im Body passt, als Fehler. *(V5)*
- **AC6** — `lint` meldet eine Story mit fehlendem/leerem/unbekanntem `parent` als Fehler. *(V6)*
- **AC7** — `lint` meldet unauflösbare, typ-fremde, selbstreferenzielle oder zyklische `depends` als Fehler. *(V7)*
- **AC8** — `lint` meldet eine fehlende `spec`-Datei oder eine `implements`-AC-Nummer, die in der Spec nicht als `AC<n>` vorkommt, als Fehler. *(V8)*
- **AC9** — `lint` meldet fehlende Pflichtfelder/Enum-Verletzungen mit Datei + Feldname. *(V9)*
- **AC10** — Inkonsistente abgeleitete Felder (`stories[]`/`progress`) sind eine `lint`-**Warnung**, kein Fehler. *(V10)*
- **AC11** — `lint` ist deterministisch, gibt je Verstoss `FEHLER|WARN <regel-id> <datei> <detail>` aus und endet mit Exit ≠ 0 nur bei ≥1 Fehler. *(V11)*

## Verträge

### `board.yaml`
```
schema_version: 1
project_slug: agent-flow
next_feature_id: 3        # nächste freie Nummer → F-003
next_story_id: 17         # nächste freie Nummer → S-017
```

### Feature-YAML (Felder § 4.1)
```
id: F-001
title: Server-Provisioning
goal: <1–3 Sätze Was/Warum>
status: Backlog            # Backlog|Planned|Active|Done|Archived
priority: P1              # P0|P1|P2|P3
spec: docs/specs/provisioning.md     # optional
definition_of_done: <grob, prüfbar>  # optional
labels: [infra, vps]                  # optional
depends: [F-000]                      # optional, Feature-IDs
owner: alex                           # optional
stories: [S-014, S-015]               # abgeleitet
progress: "2/3 done · 1 in progress"  # abgeleitet
created_at: 2026-06-14T00:00:00Z
updated_at: 2026-06-14T00:00:00Z
```

### Story-YAML (Felder § 4.2)
```
id: S-014
parent: F-001            # PFLICHT, genau ein Feature
title: IONOS-Adapter
status: To Do            # To Do|In Progress|Blocked|In Review|Done|Verworfen (Schreiber: /flow)
                         #   Verworfen = terminal (Won't-Do/Obsolete), nicht "erfolgreich" — s. story-status-verworfen
priority: P0             # P0|P1|P2|P3
spec: docs/specs/provisioning.md
implements: [AC1, AC2, AC4]
depends: [S-013]                      # optional, Story-IDs
labels: [db, security]                # optional
size_est: M                           # optional  S|M|L|XL
dispo_est: null                       # optional  EP|null  (Sicht, SoT=Ledger)
dispo_act: null                       # optional  EP|null
dispo_forecast: null                  # optional  +/-%|null
estimate_note: null                   # optional
confidence: null                      # optional  high|medium|low
tok_est: null                         # optional  Ganzzahl|null  (A-priori-Tokens, s. apriori-token-estimate)
branch: null                          # optional
pr: null                              # optional
blocked_reason: null                  # optional
created_at: 2026-06-14T00:00:00Z
updated_at: 2026-06-14T00:00:00Z
done_at: null
```

### `lint`-Regel-IDs (stabil, für CLI-Ausgabe)
`ID-DUP` (V5) · `PARENT-MISSING` (V6) · `DEPENDS-UNRESOLVED` / `DEPENDS-CYCLE` (V7) · `AC-MISSING` / `SPEC-MISSING` (V8) · `FIELD-REQUIRED` / `ENUM-INVALID` (V9) · `ROLLUP-STALE` (V10, Warnung) · `STORY-UNSPEC` (V3, Warnung — importierte Story ohne `spec`/`implements`).

## Edge-Cases & Fehlerverhalten

- **`board.yaml` fehlt** → Board nicht initialisiert; `lint` meldet das als Fehler `FIELD-REQUIRED board.yaml`.
- **Leeres `board/`** (kein Feature/keine Story) → `lint` grün (kein Fehler), nichts zu prüfen.
- **Story ohne `implements`** → `FIELD-REQUIRED` (PFLICHT bei nativen Stories); bei importierten Stories (Feld `github_issue` gesetzt) → `WARN STORY-UNSPEC` (kein FEHLER), da der Marker im GitHub-Issue fehlte — Owner zieht nach.
- **Story ohne `spec`** (importiert) → `WARN STORY-UNSPEC` (kein FEHLER), analog zu `implements`. Native Stories ohne `spec` → `FIELD-REQUIRED`.
- **Verwaiste Datei** (z.B. Story-Datei, deren `parent` archiviert wurde) → `parent` existiert noch als Datei → kein Fehler; ist das Feature gelöscht → `PARENT-MISSING`.
- **Dateiname-Slug ≠ `title`-Slug** → kein Fehler (Slug ist nur Komfort; Body-`id` zählt).
- **Doppelte `depends`-Einträge** → dedupliziert behandelt, kein Fehler.

## NFRs

- **Diff-Freundlichkeit:** ein Item = eine Datei = ein Diff; stabile Feld-Reihenfolge, damit git-Diffs minimal bleiben.
- **Determinismus:** `lint` ohne LLM, rein mechanisch; reproduzierbares Ergebnis.
- **Merge-arm:** append-arme Felder; `updated_at`-Konflikte sind trivial lösbar (§11).

## Nicht-Ziele

- CLI-Verben/Queue-Logik selbst ([[board-cli]]).
- ID-Vergabe-Mechanik (Zähler hochzählen) — Feld-Definition hier, Vergabe in [[board-cli]].
- Skelett-Anlage beim Projektstart ([[new-project-board]]).
- Migration aus GitHub ([[board-github-export]]).
- AC-Definition selbst (die leben in `docs/specs/`).

## Abhängigkeiten

- `docs/architecture/board-subsystem.md` §3–§6, §11 — bindendes Detailkonzept.
- [[board-cli]] — implementiert `lint` gegen diese Regeln + die ID-Vergabe.
- [[metrics-ledger]] — SoT der `dispo_act`/`tok`-Werte, die die Story-YAML spiegelt.
