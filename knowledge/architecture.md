# Knowledge Pack: architecture  (Domäne — vom architekt genutzt)

Patterns für Software-Architektur. Vom `architekt` geladen (sprach-übergreifend). Regel-IDs: `architecture/R<NN>`.

## Coder-Guidance  (hier: Architekt-Guidance)
- `architecture/R01` — Klare Layer-/Modul-Grenzen; Abhängigkeiten zeigen nach innen (stabile Kerne).
- `architecture/R02` — Explizite Modul-Verträge (Interfaces) statt impliziter Kopplung.
- `architecture/R03` — Entscheidungen ADR-artig dokumentieren (Kontext → Entscheidung → Konsequenz).
- `architecture/R04` — Keine vorzeitige Komplexität; so einfach wie die Anforderung erlaubt.

## Reviewer-Checklist
- Cross-Layer-Leak / zyklische Abhängigkeit → **Important**.
- Komponente ohne klare Verantwortung / God-Object → **Important**.
- Signifikante Entscheidung undokumentiert (nicht in `docs/architecture.md`) → **Suggestion**.

## Test-Approach
- n/a (Design-Doc). Konformität wird beim Code-Review gegen `docs/architecture.md` geprüft.
