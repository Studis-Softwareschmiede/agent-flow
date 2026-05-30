# Knowledge Pack: java

Expertise für Java. Geladen bei `profile.language: java`. Regel-IDs: `java/R<NN>`.

## Coder-Guidance
- `java/R01` — Ressourcen via try-with-resources schließen.
- `java/R02` — Keine geschluckten Exceptions (`catch {}`); loggen oder weiterreichen.
- `java/R03` — Immutability bevorzugen; Null-Sicherheit via `Optional`/Guards.
- `java/R04` — **Virtual Threads (JDK 21+, stabil):** I/O-gebundene Tasks via `Thread.ofVirtual().start(...)` oder `Executors.newVirtualThreadPerTaskExecutor()` skalieren ohne manuellen Thread-Pool; kein `synchronized`-Block im Hot-Path (pinnt Platform-Thread). Quelle: [JEP 444](https://openjdk.org/jeps/444) · [JDK 21 Release](https://openjdk.org/projects/jdk/21/)
- `java/R05` — **Sequenced Collections (JDK 21+, stabil):** Neue Interfaces `SequencedCollection`, `SequencedSet`, `SequencedMap` bieten einheitliche `getFirst()`/`getLast()`/`reversed()`-API; `List`, `Deque`, `LinkedHashSet`, `LinkedHashMap`, `SortedSet`, `SortedMap` implementieren diese direkt — keine manuellen Index-Workarounds mehr. Quelle: [JEP 431](https://openjdk.org/jeps/431) · [Oracle Docs JDK 21](https://docs.oracle.com/en/java/javase/21/core/creating-sequenced-collections-sets-and-maps.html)
- `java/R06` — **ZGC non-generational Mode entfernt (JDK 25 LTS):** Flag `-XX:+ZGenerational` ist obsolet und führt zum JVM-Startabbruch; Generational ZGC war bereits Default seit JDK 23 (JEP 474) und wurde in JDK 25 alleiniger Modus (JEP 490). Bei Migration 21→25: Flag aus JVM-Optionen entfernen. Quelle: [JEP 490](https://openjdk.org/jeps/490) · [JEP 474](https://openjdk.org/jeps/474)

## Reviewer-Checklist
- Nicht geschlossene Ressourcen (Stream/Connection) → **Critical**.
- Leerer `catch` ohne Log/Handling → **Important**.
- Geteilter mutabler State ohne Synchronisation → **Critical**.
- Secrets im Code → **Critical**.
- `synchronized`-Block in Virtual-Thread-Hot-Path (pinnt Platform-Thread) → **Important** (seit JDK 21).
- `ZGenerational`-Flag in JVM-Optionen bei JDK 25+ → **Critical** (JVM startet nicht).

## Test-Approach
- Build (Maven/Gradle) grün; Unit-Tests; Smoke-Run.
