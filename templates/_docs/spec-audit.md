# Spec-Audit-Log

> Logbuch der `/agent-flow:reconcile`-Läufe (Stufe 1 Form + Stufe 2 Inhalt). Pro Lauf **ein** Block: Kopf = Datum, darunter je **eine Zeile pro berührtem Dokument** (z.B. „Spec X auf use-case-2.0 konvertiert" / „Konzept Y nachgezogen"). **Neueste Block oben.** Keine Tabelle, keine Begründung, keine Fundstellen — nur die getroffenen Änderungen (durable Historie). Eine Stufe ohne Änderung erzeugt keine Zeile und keinen Block (kein Rauschen). Vertrag: `docs/architecture/reconcile-subsystem.md` §4; Acceptance-Kriterien: `docs/specs/reconcile.md` AC10/AC11.
>
> Geschrieben **ausschließlich** von `scripts/spec-audit-append.sh` (append-prepend — neuer Block wird unter diesem Kopf eingefügt, ältere Blöcke rutschen nach unten). Diese Datei wird angelegt, sobald der erste Lauf etwas zu protokollieren hat — von Hand nichts darunter ergänzen.
