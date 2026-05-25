# Knowledge Pack: java

Expertise für Java. Geladen bei `profile.language: java`. Regel-IDs: `java/R<NN>`.

## Coder-Guidance
- `java/R01` — Ressourcen via try-with-resources schließen.
- `java/R02` — Keine geschluckten Exceptions (`catch {}`); loggen oder weiterreichen.
- `java/R03` — Immutability bevorzugen; Null-Sicherheit via `Optional`/Guards.

## Reviewer-Checklist
- Nicht geschlossene Ressourcen (Stream/Connection) → **Critical**.
- Leerer `catch` ohne Log/Handling → **Important**.
- Geteilter mutabler State ohne Synchronisation → **Critical**.
- Secrets im Code → **Critical**.

## Test-Approach
- Build (Maven/Gradle) grün; Unit-Tests; Smoke-Run.
