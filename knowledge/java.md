# Knowledge Pack: java

Expertise für Java. Geladen bei `profile.language: java`. Regel-IDs: `java/R<NN>`.

## Coder-Guidance
- `java/R01` — Ressourcen via try-with-resources schließen.
- `java/R02` — Keine geschluckten Exceptions (`catch {}`); loggen oder weiterreichen.
- `java/R03` — Immutability bevorzugen; Null-Sicherheit via `Optional`/Guards.
- `java/R04` — **Virtual Threads (JDK 21+, stabil):** I/O-gebundene Tasks via `Thread.ofVirtual().start(...)` oder `Executors.newVirtualThreadPerTaskExecutor()` skalieren ohne manuellen Thread-Pool. **JDK 21–23:** `synchronized`-Block im Hot-Path pinnt den Platform-Thread → vermeiden, stattdessen `ReentrantLock` verwenden. **JDK 24+ (JEP 491):** Pinning durch `synchronized` behoben; `ReentrantLock`-Workaround dort optional. Quelle: [JEP 444](https://openjdk.org/jeps/444) · [JEP 491](https://openjdk.org/jeps/491) · [JDK 21 Release](https://openjdk.org/projects/jdk/21/)
- `java/R05` — **Sequenced Collections (JDK 21+, stabil):** Neue Interfaces `SequencedCollection`, `SequencedSet`, `SequencedMap` bieten einheitliche `getFirst()`/`getLast()`/`reversed()`-API; `List`, `Deque`, `LinkedHashSet`, `LinkedHashMap`, `SortedSet`, `SortedMap` implementieren diese direkt — keine manuellen Index-Workarounds mehr. Quelle: [JEP 431](https://openjdk.org/jeps/431) · [Oracle Docs JDK 21](https://docs.oracle.com/en/java/javase/21/core/creating-sequenced-collections-sets-and-maps.html)
- `java/R06` — **ZGC non-generational Mode obsolete seit JDK 24 (JEP 490):** Flag `-XX:-ZGenerational` erzeugt ab JDK 24 eine Obsolete-Warning beim JVM-Start (kein Startabbruch); Removal mit Startabbruch ist für ein zukünftiges Release angekündigt, aber noch nicht einem bestimmten JDK zugewiesen. Generational ZGC war bereits Default seit JDK 23 (JEP 474). Bei Migration auf JDK 24+: Flag vorsorglich aus JVM-Optionen entfernen. Quelle: [JEP 490](https://openjdk.org/jeps/490) · [JEP 474](https://openjdk.org/jeps/474)
- `java/R07` — **Framework-/Build-Pack laden:** ist `profile.frameworks` oder `profile.build` gesetzt, lade zusätzlich die entsprechenden Packs aus `knowledge/frameworks/` und `knowledge/build/` (siehe `docs/architecture/framework-build-subsystem.md` §3). Spring-spezifische Regeln stehen NICHT in diesem Java-Pack, sondern in `frameworks/spring-boot-<major>.md`.

## Reviewer-Checklist
- Nicht geschlossene Ressourcen (Stream/Connection) → **Critical**.
- Leerer `catch` ohne Log/Handling → **Important**.
- Geteilter mutabler State ohne Synchronisation → **Critical**.
- Secrets im Code → **Critical**.
- `synchronized`-Block in Virtual-Thread-Hot-Path → **Important** (gilt für JDK 21–23; seit JDK 24 durch JEP 491 behoben).
- `ZGenerational`-Flag in JVM-Optionen bei JDK 24+ → **Important** (Obsolete-Warning; Removal/Startabbruch in einem zukünftigen Release angekündigt).

## Test-Approach
- Build (Maven/Gradle) grün; Unit-Tests; Smoke-Run.
