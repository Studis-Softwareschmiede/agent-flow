# Spec-Audit-Logbuch

> **Zweck:** wiederkehrender Code→Doc-Abgleich (`/agent-flow:adopt reconcile`). Hält fest, *wann* gegen
> welchen Code-Stand geprüft wurde, *welche* Abweichungen gefunden und *wie* sie aufgelöst wurden.
> **Durable Entscheidungs-Historie** — NICHT die abgeleitete Roh-Drift-Liste (die ist ephemer). Source of
> Truth bleiben `concept.md` / `architecture.md` / `specs/`.
> Vertrag (in agent-flow): `docs/architecture/reconcile-subsystem.md`.
>
> Wird von `/adopt reconcile` ergänzt, **nicht** von Hand gepflegt (Ausnahme: die won't-fix-Begründung).
> Neueste Läufe oben.

<!-- VORLAGE — pro Reconcile-Lauf einen Block wie diesen oben einfügen:

## Lauf YYYY-MM-DD · HEAD `<kurz-sha>`

- **Drifts gefunden:** <n>
- **Doc nachgezogen:** <n>   · **Rückbau geplant:** <n>   · **Akzeptiert (won't-fix):** <n>

| # | Bereich | Code-Fundstelle | Spec/AC | Richtung | Status |
|---|---|---|---|---|---|
| 1 | <Bereich> | path/to/file:42 | spec-slug#AC3 (oder „fehlt") | doc-nachziehen | doc-nachgezogen → PR #<n> |
| 2 | <Bereich> | path/to/file:108 | „fehlt" | code-rückbau | rückbau-geplant → Issue #<n> |
| 3 | <Bereich> | path/to/file:7 | spec-slug#AC1 | akzeptiert | won't-fix: <kurze Begründung> |

-->

_Noch kein Reconcile-Lauf. Erster Abgleich: `/agent-flow:adopt reconcile` im Repo-Root._
