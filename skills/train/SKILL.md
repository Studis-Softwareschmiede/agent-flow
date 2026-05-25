---
name: train
description: Startet den train-Agenten — recherchiert im Netz aktuelle Patterns für eine Sprache und öffnet einen PR, der knowledge/<lang>.md aktualisiert (mit Quellen, PR+Gate). Aufruf: /train <language>.
---

# /train <language>

Starte den **train**-Agenten (Task-Tool) für die genannte Sprache (z.B. `/train flutter`). Er liest das aktuelle `knowledge/<lang>.md`, recherchiert aktuelle/autoritative Quellen, filtert streng auf Neues+Belegtes und öffnet einen **PR** mit Quellen (+ `LEARNINGS.md`-Zeile, Board-Karte `Proposed`).

**Merge erst nach `reviewer`-Check + deinem Approve** (Gate §5).
