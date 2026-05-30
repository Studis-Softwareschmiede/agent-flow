# LEARNINGS — Self-Improvement-Ledger

Eine Zeile pro Promotion (von `retro`/`train`/`teamLeader`, via PR). Status:
`Proposed → Merged → Measuring → Validated | Reverted`. Spiegelt das Improvement-Board.

| ID | Datum | Pack/Skill | Regel | Quelle | PR | Status |
|----|-------|------------|-------|--------|----|--------|
| `coder/R01` | 2026-05-26 | `agents/coder.md` | Kein Gold-Plating über die Spec hinaus — strikt nur die genannten AC; als Nicht-Ziel Gelistetes nicht bauen; fehlt etwas → SPEC-LÜCKE statt eigenmächtig ergänzen | sandbox-3 `.claude/lessons/coder.md` #1 (wiederkehrendes Spec-Drift-Muster) | retro/coder-no-gold-plating | Proposed |
| `css/R04` | 2026-05-26 | `knowledge/css.md` | `@container` (Size Container Queries) für komponenten-bezogene Responsiveness statt globaler `@media`; braucht `container-type` am Vorfahren — seit Aug 2025 Baseline „Widely available" | [web.dev Baseline digest Aug 2025](https://web.dev/blog/baseline-digest-aug-2025) · [MDN Container Queries](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Container_Queries) | train/css | Proposed |
| `css/R05` | 2026-05-26 | `knowledge/css.md` | `light-dark()` für Light/Dark-Farben in einer Deklaration; erfordert `color-scheme: light dark` — Baseline „Newly available" seit Mai 2024 | [MDN light-dark()](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/light-dark) | train/css | Proposed |
| `css/R06` | 2026-05-26 | `knowledge/css.md` | `:has()` ist nicht forgiving → ganzer Selektor-Block fällt aus, wenn nicht unterstützt; in `:is()`/`:where()` kapseln — Baseline „Newly available" seit Dez 2023 | [MDN :has()](https://developer.mozilla.org/en-US/docs/Web/CSS/:has) | train/css | Proposed |
| `java/R04` | 2026-05-30 | `knowledge/java.md` | Virtual Threads (JEP 444) stabil seit JDK 21 LTS: `Thread.ofVirtual()` / `Executors.newVirtualThreadPerTaskExecutor()`; kein `synchronized` im Hot-Path | [JEP 444](https://openjdk.org/jeps/444) | train/knowledge/java-20260530 | Proposed |
| `java/R05` | 2026-05-30 | `knowledge/java.md` | Sequenced Collections (JEP 431) stabil seit JDK 21 LTS: `SequencedCollection`/`SequencedMap` mit `getFirst()`/`getLast()`/`reversed()` | [JEP 431](https://openjdk.org/jeps/431) | train/knowledge/java-20260530 | Proposed |
| `java/R06` | 2026-05-30 | `knowledge/java.md` | ZGC non-generational Mode entfernt in JDK 25 LTS (JEP 490): `-XX:+ZGenerational` → JVM-Startabbruch; Flag bei Migration 21→25 entfernen | [JEP 490](https://openjdk.org/jeps/490) | train/knowledge/java-20260530 | Proposed |
