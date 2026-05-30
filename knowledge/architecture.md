# Knowledge Pack: architecture  (Domäne — vom architekt genutzt)

Patterns für Software-Architektur. Vom `architekt` geladen (sprach-übergreifend). Regel-IDs: `architecture/R<NN>`.

## Coder-Guidance  (hier: Architekt-Guidance)
- `architecture/R01` — Klare Layer-/Modul-Grenzen; Abhängigkeiten zeigen nach innen (stabile Kerne).
- `architecture/R02` — Explizite Modul-Verträge (Interfaces) statt impliziter Kopplung.
- `architecture/R03` — Entscheidungen ADR-artig dokumentieren (Kontext → Entscheidung → Konsequenz).
- `architecture/R04` — Keine vorzeitige Komplexität; so einfach wie die Anforderung erlaubt.
- `architecture/R05` — **Monolith-First / Modulith-First**: Neue Systeme als modularen Monolithen starten und Services erst bei nachgewiesenem Bedarf extrahieren — Servicegren­zen lassen sich im Betrieb verlässlicher ziehen als vorab. Consensus: martinfowler.com (MonolithFirst, 2015), microservices.io (Microservice Architecture, Richardson). Abweichung begründen im ADR. | Quelle: [martinfowler.com/bliki/MonolithFirst](https://martinfowler.com/bliki/MonolithFirst.html)
- `architecture/R06` — **Transactional Outbox** (kanonisches Pattern): Wenn ein Service atomar DB-State und Nachrichten/Events publizieren muss, die Nachricht zuerst in eine `outbox`-Tabelle schreiben (gleiche Transaktion) und per separatem Relay (Polling Publisher oder CDC/Transaction-Log-Tailing) an den Broker weiterleiten — garantiert Exactly-Once-Delivery ohne 2PC. Consumer müssen idempotent sein. | Quelle: [microservices.io/patterns/data/transactional-outbox](https://microservices.io/patterns/data/transactional-outbox.html)
- `architecture/R07` — **ADR-Format MADR 4.0** als empfohlenes Template: Pflichtfelder `Context and Problem Statement` · `Considered Options` · `Decision Outcome`; optional `Decision Drivers`, `Confirmation`, `Pros and Cons of the Options`. Gegenüber dem ursprünglichen Nygard-Format (2011) ergänzt MADR explizite Trade-off-Abschnitte und YAML-Frontmatter (Status, Datum, Entscheider). MADR 4.0.0 veröffentlicht September 2024. | Quelle: [adr.github.io/madr](https://adr.github.io/madr/) · [github.com/adr/madr](https://github.com/adr/madr)

## Reviewer-Checklist
- Cross-Layer-Leak / zyklische Abhängigkeit → **Important**.
- Komponente ohne klare Verantwortung / God-Object → **Important**.
- Signifikante Entscheidung undokumentiert (nicht in `docs/architecture.md`) → **Suggestion**.

## Test-Approach
- n/a (Design-Doc). Konformität wird beim Code-Review gegen `docs/architecture.md` geprüft.
