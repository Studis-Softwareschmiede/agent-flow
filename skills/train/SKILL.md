---
name: train
description: Startet den train-Agenten — recherchiert im Netz aktuelle Patterns für eine Sprache und öffnet einen PR, der knowledge/<lang>.md aktualisiert (mit Quellen, PR+Gate). Aufruf: /train <language>.
---

# /train <language>

Starte den **train**-Agenten (Task-Tool) für die genannte Sprache (z.B. `/train flutter`). Er liest das aktuelle `knowledge/<lang>.md`, recherchiert aus **Primär-/autoritativen Quellen** (offizielle Docs/Specs/Release-Notes — keine Einzel-Blogs), priorisiert **faktische Deltas** (Deprecations/neue stabile APIs/Breaking Changes) vor subjektiver „Best-Practice", promotet **max. 3 Regeln/Lauf** und öffnet einen **PR** mit Quell-Links (+ `LEARNINGS.md`-Zeile, Board-Karte `Proposed`).

**Merge erst nach `reviewer`-Check + deinem Approve** (Gate §5).
