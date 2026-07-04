# Ideen-Inbox

Durables, append-only Register bereichsfremder Anforderungen — denen kein bestehender Bereich zugeordnet wurde, aber die kein Konzept-Widerspruch darstellen.

Jeder Eintrag trägt: `titel`, `beschreibung`, `begruendung` (1 Satz), `status: Idee`, ISO-8601-UTC-Zeitstempel. Bestehende Einträge werden nie überschrieben — neue Einträge werden angehängt (newest-first, chronologisch).

Einträge können später durch `board area split` ein optionales `area`-Feld erhalten, wenn sie einem Ziel-Bereich zugeordnet werden.

---

*Diese Datei ist das Source of Truth für bereichsfremde Anforderungen. Sie wird durch den `requirement`-Agenten gepflegt (`docs/specs/requirement-area-intake.md` AC4/AC7).*
