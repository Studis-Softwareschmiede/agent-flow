---
spec_format: use-case-2.0
status: active
---

# Spec: Security-Pack immer aktuell — Lern-Kreis härten

> Schließt die drei Lücken, die den `security`-Pack (`knowledge/security.md`) daran hindern, verlässlich frisch zu
> bleiben: (B) keine fest verankerten Quellen, (C) nur passiver Frische-Nudge, (D) unklare train/retro-Zuständigkeit.
> Bindender Rahmen: `docs/architecture/red-team-subsystem.md` §5. Feature: F-030.

## Kontext & Motivation

`train` und `retro` halten Wissen aktuell — für Security ist das Zusammenspiel aber unscharf:
- **train** kennt `/train security` und setzt `last_trained`, hat aber **keine feste Quellen-Liste** (anders als
  Framework-Packs mit `primary_sources`/`non_sources`). Ergebnis: jeder Lauf sucht Quellen neu → weniger
  deterministisch/auditierbar.
- **retro** darf in Domänen-Packs schreiben, aber die **Zuständigkeit** (welche Regeln train, welche retro) ist im
  `security`-Pack — anders als bei der A/B-Trennung der Framework-Packs — **nicht** getrennt → Kollisions-Risiko auf `security/R<NN>`.
- Frische ist nur ein **passiver** `/flow`-Nudge bei > 90 Tagen.

## Akzeptanzkriterien

- **AC1 — Feste Quellen-Verankerung.** `knowledge/security.md` trägt oben einen strukturierten Header mit
  `primary_sources:` (mindestens: OWASP Top 10, NIST CSRC / SP 800-63 / SP 800-131, IETF datatracker/RFC,
  PortSwigger Web Security Academy) und `non_sources:` (mindestens: dev.to, medium.com, stackoverflow.com,
  geeksforgeeks.org) — analog zum Header der Framework-Packs.
- **AC2 — `/train security` respektiert die Quellen.** `agents/train.md` wird so ergänzt, dass der `security`-Pfad
  nur aus `primary_sources` zitiert und Treffer aus `non_sources` ignoriert (verbindlich, wie bei Framework-Packs).
  Das bestehende Verhalten „`last_trained` bei jedem Lauf auf heute" bleibt.
- **AC3 — Zwei kollisionsfreie Lanes.** `knowledge/security.md` dokumentiert zwei Regel-Lanes:
  **Norm-Lane** `security/R<NN>` (train-Hoheit, externe Standards) und **Einsatz-Lane** `security/E<NN>`
  (retro-Hoheit, Erfahrung aus echten Läufen). Die bestehenden R01–R16 bleiben unverändert in der Norm-Lane;
  eine neue Sektion nimmt die Einsatz-Lane auf (anfangs leer/mit Erklärung).
- **AC4 — retro-Vertrag nachgezogen.** `agents/retro.md` hält fest: für den `security`-Domänen-Pack schreibt retro
  **ausschließlich** in die Einsatz-Lane (`security/E<NN>`), **nie** in die Norm-Lane (`security/R<NN>`).
  Verstoß = harter Reviewer-Befund (analog zur „nur Sektion B"-Regel der Framework-Packs).
- **AC5 — reviewer-Enforcement.** `agents/reviewer.md` prüft bei einem Pack-PR gegen `security.md`, dass die
  Lane-Trennung eingehalten ist (train-PR ändert nur R-Lane; retro-PR nur E-Lane).
- **AC6 — Frische-Nudge geschärft.** `skills/flow/SKILL.md` verweist im Security-Frische-Nudge zusätzlich auf die
  **self-updating Ebene** (tagesaktuelle CVEs → Dependabot + geplanter Scanner-Lauf gehören NICHT in den Pack) —
  damit klar ist, dass der 90-Tage-Nudge nur die **durablen Prinzipien** betrifft, nicht die Tages-CVEs. Der
  Schwellwert bleibt 90 Tage.
- **AC7 — Konsistenz.** `board lint` bleibt grün; keine Regel-ID-Kollision zwischen R- und E-Lane; die
  3-Speed-Kopfnote im Pack ist mit `red-team-subsystem.md` §5 konsistent.

## Bewusst NICHT

- Kein neuer Schwellwert < 90 Tage (durable Prinzipien bewegen sich langsam; die schnelle Ebene ist die Scanner-Feeds).
- Kein automatischer `train`-Lauf ohne PR (die PR+Gate-Mechanik bleibt).
- Keine inhaltliche Änderung an R01–R16.
