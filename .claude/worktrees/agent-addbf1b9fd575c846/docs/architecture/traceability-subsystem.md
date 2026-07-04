# Traceability-Subsystem — Spec↔Test-Rückverfolgbarkeit

> **Status:** akzeptiert (Stufe 1). Quer-Achse wie `model-tier-subsystem.md` / `metrics-subsystem.md`.
> **Source of Truth** für die Spec↔Test-Verknüpfung. Sprach-**neutral**: dieses Dokument definiert den
> Vertrag und das kanonische Token; das physische **Idiom** je Sprache liegt im jeweiligen
> Knowledge Pack (`knowledge/<lang>.md`, Abschnitt `## Spec-Tagging`).

## 1. Zweck & Prinzip

Jede Anforderung ist auf den sie prüfenden Test rückführbar — und zurück. Das macht „**welcher Test
deckt Regel X?**" maschinell beantwortbar (Audit, regulatorischer Nachweis) und schliesst die Lücke, dass
die bisherige Spur (`Spec-ID → Board-Item → Commit/PR`, CONCEPT §4d) beim Commit endet und nicht bis in
den Testcode reicht.

**Leitprinzip — die Map wird ABGELEITET, nie von Hand gepflegt.** Eine handgepflegte Spec→Test-Tabelle
rottet (genau das Problem, das §4d vermeidet). Stattdessen tragen die Tests selbst ein maschinenlesbares
**Trace-Tag**; der `tester` (bzw. CI) parst die Tags zur Laufzeit und berechnet die Abdeckung. Ein
fehlender Tag fliegt im Gate auf → **selbst-korrigierend statt disziplin-abhängig**, dieselbe Logik wie
das harte Drift-Gate.

## 2. Drei Ebenen

| Ebene | Was | Wo |
|---|---|---|
| **1 — Vertrag** (sprach-neutral) | *Jeder Test deklariert, welche AC/BR er abdeckt.* Kanonisches Token + Coverage-Regel. | **dieses Dokument** + `AGENTS.md`-Verträge |
| **2 — Idiom** (pro Sprache) | *Wie* das Tag physisch ausgedrückt wird + **Extraktions-Rezept** (Regex/Befehl). | `knowledge/<lang>.md` → `## Spec-Tagging` |
| **3 — Map** (abgeleitet) | Coverage-Berechnung + optionaler `docs/traceability.md`-Report. | zur Laufzeit vom `tester`/CI erzeugt, **nie committet als Wahrheit** |

## 3. Kanonisches Trace-Token (Ebene 1)

Unabhängig vom Sprach-Idiom muss aus jedem Test genau diese Information rekonstruierbar sein:

```
TRACE-TOKEN ::= "@trace" SP SPEC-SLUG "#" CRITERION ( "," CRITERION )*
SPEC-SLUG   ::= kebab-case (= die Spec-ID aus dem Frontmatter, z.B. "user-login")
CRITERION   ::= "AC" DIGITS            # ein Acceptance-Kriterium
              | "BR-" DIGITS           # eine Geschäftsregel (3-stellig, z.B. BR-002)
```

**Beispiel (kanonisch):** `@trace user-login#AC1,AC3,BR-002`

- **Kanonische Extraktions-Regex** (jedes Pack-Rezept MUSS (slug, criterion)-Paare hierzu kompatibel liefern):
  `@trace\s+([a-z0-9][a-z0-9-]*)#((?:AC\d+|BR-\d+)(?:,(?:AC\d+|BR-\d+))*)`
- Ein Test darf mehrere Kriterien/mehrere Specs taggen. Die kleinste rekonstruierbare Einheit ist das
  Paar **(spec-slug, criterion)**.
- **Namensraum-Abgrenzung:** `BR-NNN` = **Projekt-Geschäftsregel** (lebt in `docs/architecture.md` bzw.
  `docs/data-model.md`). NICHT zu verwechseln mit `lang/R<NN>` = **Fabrik-Qualitätsregel** der Knowledge
  Packs (z.B. `java/R07`). Zwei Namensräume, ein Mechanismus.

## 4. Coverage-Gate (Ebene 3, durchgesetzt vom `tester`)

Für die im Board-Item genannten AC (`implements AC<…>`) der referenzierten Spec gilt **hart**:

1. **AC-Deckung:** jede genannte `AC<n>` hat **≥ 1** Test, dessen Trace-Tags `<spec-slug>#AC<n>` enthalten.
2. **BR-Deckung:** jede `BR-NNN`, die von einer genannten AC referenziert wird, hat **≥ 1** deckenden Test
   — direkt getaggt (`#BR-NNN`) **oder** transitiv über einen Test, der die referenzierende AC deckt.
3. Verletzung (1) oder (2) → **`Test-Gate: FAIL`** (Grund: `TRACE-GAP: <spec>#<crit> ungedeckt`).

Reiner Refactor/Typo ohne neues Verhalten erzeugt keine neue AC → keine neue Tag-Pflicht
(**Proportionalität**, analog Drift-Gate).

## 5. Abgeleiteter Report (optional)

Der `tester` MAY einen `docs/traceability.md` als **Build-Artefakt** emittieren (Matrix AC/BR × Test).
Er ist **derived** — bei Konflikt gewinnt immer der aus den Tags geparste Ist-Zustand, nie die Datei.
Darum: nicht als Source of Truth behandeln, gitignore oder als CI-Artefakt führen.

## 6. Touchpoints

- `requirement` — vergibt stabile `AC<n>`-IDs; ACs referenzieren `BR-NNN` (siehe `specs/_template.md`).
- `coder` — schreibt pro Test das Trace-Tag gemäss `knowledge/<lang>.md` → `## Spec-Tagging`.
- `reviewer` — prüft: referenzierte `BR-NNN` existieren in `architecture.md`/`data-model.md`; Tests tragen
  Trace-Tags (fehlend = **Important**).
- `tester` — parst Tags via Pack-Rezept, rechnet Coverage-Gate (§4), setzt Test-Gate; optional Report (§5).
- `knowledge/<lang>.md` — `## Spec-Tagging`: Idiom + Extraktions-Rezept; `train` hält es bei
  Framework-API-Änderungen frisch (PR + Gate).
- CI (`build.yml`, optional) — denselben Coverage-Check als harten Gate vor dem Image spiegeln.

## 7. Bewusst NICHT

- Keine handgepflegte Trace-Matrix (Ebene 3 ist immer abgeleitet).
- Keine sprach-spezifische Annotation im Core (das Idiom lebt im Pack; der Core kennt nur das Token).
- Kein eigener Trace-Agent (Pack-Prinzip: Rolle ≠ Expertise).
