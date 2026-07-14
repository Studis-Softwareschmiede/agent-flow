---
id: output-shaping-classA-filter
title: Ausgabe-Token-Diät — Weg A (Eigenbau-Filter für Klasse-A-Befehle), Design-first
status: active
area: rollen-agenten
version: 1
spec_format: use-case-2.0
---

# Spec: Ausgabe-Token-Diät — Weg A (Eigenbau-Filter), Design-first  (`output-shaping-classA-filter`)

> **Schicht 3 von 3.** Diese Story ist **Design-first**: Deliverable ist eine **Architektur-Entscheidung** (docs/architecture), KEIN Filter-Code. Die Umsetzung ist eine spätere Story, die erst nach freigegebenem Design startet.

## Zweck
Weg A aus dem ADR [`docs/architecture/output-token-shaping.md`](../architecture/output-token-shaping.md): den realen, sicheren Klasse-A-Nutzen (~65–80 % laut Pilot S-345) durch einen **eigenen** Filter einfangen — **ohne** Fremd-Binary im Hot-Path. **Kritische Lehre aus dem Pilot:** RTKs Schwäche war eine naive Tail-Heuristik, die auf Gate-kritischen Befehlen (Tests) das Fehlersignal verlor. Ein Eigenbau darf **denselben Fehler nicht wiederholen** — daher ist die zentrale Design-Frage nicht „wie kürzen", sondern „wie garantieren, dass Klasse B/C **nie** angefasst wird".

## Acceptance-Kriterien (Design-Deliverables)

- **AC1 — Mechanismus-Entscheidung.** Bewerten und begründet festlegen: **PreToolUse-Hook** (prozessweit, Command-Muster-basiert) vs. **Wrapper-Befehl** (Agenten rufen bewusst `<wrapper> <cmd>` nur für Klasse A) vs. **reine Konvention**. Kriterien: Fidelity-Garantie für Klasse B/C, Wirkungsradius bei Fehlern, Wartbarkeit, Nachvollziehbarkeit. Die Hot-Path-Risiken aus der ADR-Supply-Chain-Bewertung (§3.4) gelten für Eigencode analog.
- **AC2 — Klasse-B/C-Schutz als harte Invariante.** Das Design MUSS eine **strukturelle** Garantie enthalten (nicht nur eine Konvention), dass `git diff`, Test-/Build-Output und Verbatim-Quellen **nie** durch den Filter laufen — z. B. strikte Allowlist statt Denylist, fail-open bei Unbekanntem, kein generischer „alle Befehle"-Modus.
- **AC3 — Nur konservative, generische Tricks.** Festlegen, welche Kürzungen erlaubt sind (Dedup identischer Zeilen **mit Count**, Truncation **mit** Kontext-Erhalt) — nie kommentarloses Abschneiden (ADR §3.3).
- **AC4 — Anbindung an die Pack-`Output-Contract`-Schemata (ADR §6/AC6).** Wie liest der Filter die toolchain-spezifischen Signal-Regeln aus `knowledge/<lang>.md`? (Nur relevant, falls das Design Klasse-B je einbeziehen wollte — Default: Klasse B bleibt außen vor, s. AC2.)
- **AC5 — Fidelity-Testplan.** Ein reproduzierbarer Test, der VOR jeder Aktivierung beweist, dass Gate-Ausgaben unverändert durchlaufen (analog zur Pilot-Gegenprobe S-345) — kein Rollout ohne bestandenen Fidelity-Test.

## Nicht-Ziele
- **Kein** Filter-Code in dieser Story (Design-first).
- **Keine** Wiederholung des RTK-Fehlers (Filter im Hot-Path, der Gate-Signal verlieren kann).

## Abhängigkeiten
- ADR [`docs/architecture/output-token-shaping.md`](../architecture/output-token-shaping.md) (§3.0 Pilot-Befund, §3.3 Fidelity, §6 Output-Contract-Schema).
- `[[output-shaping-prompt-frugality]]` (Weg C — die risikofreie Sofortmaßnahme; Weg A ist der mittelfristige Ausbau).
