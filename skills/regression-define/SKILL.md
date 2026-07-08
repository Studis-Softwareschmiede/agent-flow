---
name: regression-define
description: Startet den regression-define-Agenten — liest die Specs eines Bereichs/Verbunds und schlägt in Alltagssprache Testfälle für die dev-gui-Redaktionsschleife vor (modus=vorschlag), oder übersetzt eine vom Owner redigierte Fassung deterministisch in Playwright-Testdatei + Datentabelle + Begleitbeschreibung und liefert als PR (modus=uebersetzen, redigierter_vorschlag via STDIN). Enthält selbst keine Test-/Übersetzungslogik — dispatcht nur agents/regression-define.md. Optionales ergebnis_datei=<absoluter-pfad> schreibt das Ergebnis-JSON zusätzlich atomar in eine Datei (headless-Konsum, dev-gui S-307). Aufruf: /agent-flow:regression-define modus=vorschlag projekt=<repo> (bereich=<id>|verbund=<name>) [stichworte=<w1,w2,…>] [ergebnis_datei=<pfad>] | echo '<json>' | claude -p '/agent-flow:regression-define modus=uebersetzen projekt=<repo> [ergebnis_datei=<pfad>]'. Im Ziel-Projekt-Repo ausführen.
---

# /agent-flow:regression-define [--cost <mode>] modus=<vorschlag|uebersetzen> …

cwd = Ziel-Projekt-Repo.

Dieser Skill ist **reines Dispatch**: er parst den Diskriminator `modus` + die zugehörigen Argumente/STDIN
und startet den **regression-define**-Agenten (`agents/regression-define.md`, Task-Tool) mit dem geparsten
Eingabe-Vertrag. Er enthält **keine eigene** Test-/Übersetzungslogik — die gesamte Fachlogik (Spec-Lesen,
Vorschlag ableiten, Secret-Heuristik, Playwright-Übersetzung, PR-Auslieferung) liegt im Agenten.

## 0. Cost-Mode auflösen

Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced` (Kurzformen `low`/`max`/`front` normalisieren;
`front`→`frontier`; siehe `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md`). Das `--cost`-Token gehört NICHT
zum Eingabe-Vertrag — vor dem Parsen von `modus=…` herausfiltern.

`regression-define` hat **keine eigene Zeile** in der Tier-Matrix (`knowledge/model-tiers.md`) — der Agent
läuft in JEDEM Cost-Mode auf seinem Frontmatter-Wert (`model: sonnet`, analog zur `balanced`-Spalte anderer
Rollen); beim Task-Dispatch in Schritt 2 daher **kein** `model`-Override mitgeben, unabhängig vom aufgelösten
Modus.

## 1. Diskriminator `modus` parsen

Der Aufruf-Text enthält genau ein `modus=vorschlag` oder `modus=uebersetzen` (nach Entfernen von `--cost …`).
Fehlt `modus` oder trägt einen anderen Wert → Fehler „`modus` muss `vorschlag` oder `uebersetzen` sein", kein
Dispatch.

### `modus=vorschlag` — Argumente durchreichen

Erwartete Argumente (Aufruf-Vertrag, `docs/specs/regression-define.md` „Verträge → Eingabe"):
```
/agent-flow:regression-define modus=vorschlag projekt=<repo> (bereich=<bereich-id> | verbund=<verbund-name>) [stichworte=<w1,w2,…>] [ergebnis_datei=<absoluter-pfad>]
```
- `projekt` **und** genau eines von `bereich=`/`verbund=` sind Pflicht — fehlt eines oder sind beide gesetzt,
  reicht der Skill den Aufruf trotzdem an den Agenten durch (der Agent validiert selbst, AC1 der Spec); der
  Skill selbst rät nichts hinzu und erfindet keinen Bereich.
- `stichworte=<w1,w2,…>` ist optional, kommaseparierte Liste → als Array durchreichen.
- `ergebnis_datei=<absoluter-pfad>` ist optional — siehe Abschnitt „Datei-Übergabe (`ergebnis_datei=`, AC12/AC13)" unten.
- **Kein STDIN nötig** in diesem Modus.

Dispatch (Task-Tool) an den `regression-define`-Agenten mit:
```
projekt: <repo>
bereich: <bereich-id> | verbund: <verbund-name>
stichworte: [<optional>, …]
modus: vorschlag
```

Rückgabe: das maschinenlesbare Rückgabeformat (siehe Spec) für die dev-gui-Redaktionsschleife — der Skill
gibt die Agenten-Ausgabe unverändert weiter.

### `modus=uebersetzen` — `redigierter_vorschlag` via STDIN

Erwarteter Aufruf (die redigierte Fassung kommt über **STDIN**, nicht als Inline-Argument — Größe):
```
echo '<redigierter_vorschlag-JSON>' | claude -p '/agent-flow:regression-define modus=uebersetzen projekt=<repo> [ergebnis_datei=<absoluter-pfad>]'
```
- `projekt=<repo>` ist Pflicht-Argument.
- `ergebnis_datei=<absoluter-pfad>` ist optional — siehe Abschnitt „Datei-Übergabe (`ergebnis_datei=`, AC12/AC13)" unten.
- **STDIN lesen:** den kompletten STDIN-Inhalt als `redigierter_vorschlag` (JSON, dieselbe Struktur wie das
  Rückgabeformat aus `modus=vorschlag`) entgegennehmen.
- **Fehlt STDIN** (leer/kein Input verfügbar) → der Skill **lehnt sofort ab** mit einer klaren Meldung
  („`modus=uebersetzen` braucht den redigierten Vorschlag als JSON über STDIN — keiner erhalten") und
  dispatcht den Agenten **nicht**. Der Skill erfindet/rekonstruiert unter keinen Umständen einen Vorschlag
  aus dem Gedächtnis oder einem vorherigen Lauf.
- Lauf 2 ist **selbst-tragend**: er braucht ausschließlich `projekt` + den per STDIN gelesenen
  `redigierter_vorschlag` — keinen Zustand aus Lauf 1 (kein Zwischenspeicher, keine Datei-Übergabe). Der
  Skill ist mit `--resume`/Session-Resume kompatibel (der Runner darf denselben Kontext fortsetzen), erzwingt
  aber selbst keinen Resume-Kontext und liest auch bei aktivem Resume den `redigierter_vorschlag` erneut aus
  STDIN, statt sich auf Lauf-1-Gedächtnis zu verlassen.

Dispatch (Task-Tool) an den `regression-define`-Agenten mit:
```
projekt: <repo>
modus: uebersetzen
redigierter_vorschlag: <STDIN-JSON, unverändert durchgereicht>
```

Der Agent übersetzt, liefert als **PR** (AC4–AC8 der Spec — Auth/Auslieferung ist bereits Teil seines
eigenen Vorgehens, `.claude/profile.md` `merge_policy`/`default_branch`). Dieser Skill selbst ruft
`ensure-gh-auth.sh` **nicht** auf — die PR-Auslieferung liegt vollständig beim Agenten.

## 1a. Datei-Übergabe (`ergebnis_datei=`, AC12/AC13)

Ist in **beiden** Modi das optionale Aufruf-Argument `ergebnis_datei=<absoluter-pfad>` gesetzt, schreibst
**du selbst** (die Skill-Session, nicht der Sub-Agent) nach dessen Rückkehr aus dem Task-Tool zusätzlich zur
Weitergabe an den Aufrufer (Schritt 2) das maschinenlesbare Ergebnis-JSON, das der `regression-define`-Agent
als Task-Result geliefert hat, **unverändert** an genau diesen Pfad:

- `modus=vorschlag` → das Rückgabeformat-JSON (siehe Spec „Rückgabeformat Testvorschlag").
- `modus=uebersetzen` → das Ergebnis-Objekt-JSON (siehe Spec „Output Modus `uebersetzen`").

Der Sub-Agent selbst kennt `ergebnis_datei` nicht und schreibt nie eine Datei — er liefert weiterhin nur
sauberes Rückgabeformat-JSON als Task-Result zurück; **du** als Skill-Session übernimmst das Schreiben.

**Typografische Anführungszeichen in JSON-String-Werten (HART, Ursachen-Fix S-061):** Alle natürlichsprachlichen
Werte, die der Sub-Agent liefert (`titel`, `schritte[]`, `pruefpunkte[]`, `hinweise[]`, Werte in `beispieldaten`,
`abgelehnt[]`, `nicht_datengetrieben[]`, …) dürfen innerhalb des Textes **ausschließlich typografische**
Anführungszeichen enthalten — deutsche „…" (bzw. ‚…' für die verschachtelte Ebene). Ein gerades `"` darf
**nirgends innerhalb eines Wertes** vorkommen, sondern ausschließlich als JSON-Delimiter selbst. Enthält ein vom
Sub-Agenten gelieferter Wert ein gerades `"` (z. B. weil eine Quell-Spec oder Owner-Eingabe es enthielt), ersetzt
du es beim Übernehmen in die zu schreibende Struktur durch die passende typografische Variante (`„`/`"` außen,
`‚`/`'` innen) — **bevor** du serialisierst. Das entfernt die Fehlerquelle strukturell: gerade Anführungszeichen
brechen sonst den umschließenden JSON-String, wenn sie unescaped in einen von Hand zusammengesetzten JSON-Text
geraten (die Ursache der drei gescheiterten Voranläufe dieser Story).

**Vorgehen (fester Pfad-Vertrag, kein eigenes Erraten des Pfads):**
1. Elternverzeichnis von `ergebnis_datei` sicherstellen: `mkdir -p "$(dirname "<ergebnis_datei>")"`.
2. **Erstschreib-Schritt — PFLICHT `Write`-Werkzeug, kein Shell-Interpolieren (HART, kein Interpretationsspielraum):**
   das Task-Result des Sub-Agenten (der Text, den du gerade im Kontext dieser Session vorliegen hast) MUSST du
   mit dem eingebauten **`Write`-Werkzeug** deiner Ausführungsumgebung direkt in eine Temp-Datei im selben
   Verzeichnis wie `ergebnis_datei` (z. B. `<ergebnis_datei>.tmp.$$`, siehe Schritt 4) schreiben — genauso, wie
   du jede andere Datei in dieser Session anlegst. Verboten für diesen Erstschreib-Schritt
   ist **jeder** Weg, der den Dateiinhalt zuerst durch einen Shell-Befehlsstring schleust, z. B.:
   - `echo '<Ergebnis-JSON>' > datei` oder `> "<ergebnis_datei>"` mit dem JSON-Text als Argument,
   - `bash -c "cat > datei <<EOF ... EOF"` bzw. jedes Heredoc, in das der dynamische Ergebnis-Text eingebettet wird,
   - `python3 -c "...<interpolierter JSON-/Text-Inhalt>..."` oder ein Node-`-e`-Einzeiler mit eingebettetem Text.
   Der Grund: sobald der natürlichsprachliche Text (der Anführungszeichen enthalten kann) Teil eines
   Shell-Befehlsstrings wird, kollidiert er mit dessen Quoting — genau das war die Ursache der drei
   gescheiterten Voranläufe dieser Story. Das `Write`-Werkzeug übernimmt den Text als Datei-Inhalt, nicht als
   Shell-Argument, und umgeht die Kollision strukturell.
3. **Danach: Serialisieren/Normalisieren, falls nötig.** Sind nach Schritt 2 noch gerade `"` in Werten
   übrig (Prüfung, kein erneutes Hand-Zusammensetzen des JSON-Texts in der Shell): eine kurze Python/Node-
   Inline-Verarbeitung darf die bereits per `Write` geschriebene Temp-Datei **lesen** (Pfad als Argument) und
   normalisiert **zurück in dieselbe Temp-Datei** schreiben (`json.load`/`json.dump` bzw. `JSON.parse`/`JSON.stringify`
   auf Dateiinhalt, nie auf einen interpolierten Shell-String). Werte zuvor gemäß obigem Absatz auf
   typografische Anführungszeichen normalisiert.
4. **Sicherheitsnetz — Selbstvalidierung auf der TEMP-Datei, VOR dem Veröffentlichen (HART, PFLICHT,
   verifizierbar, Reihenfolge kritisch):** die **Temp-Datei** (noch NICHT den Zielpfad!) mit
   `python3 scripts/validate-json.py <temp-datei>` gegenprüfen (Exit-Code `0` = valide). Wichtig: **niemals**
   `python3 -c "...<interpolierter JSON-/Text-Inhalt>..."` verwenden — das erzeugt dieselbe Bash-Quoting-Kollision
   (Anführungszeichen vs. Apostroph), die frühere Anläufe dieser Story scheitern ließ. `scripts/validate-json.py`
   nimmt **ausschließlich den Dateipfad als Argument** entgegen und liest den Inhalt selbst vom Dateisystem
   (`sys.argv[1]`, `json.load`) — der Inhalt wird nie in die Shell interpoliert. Meldet die Prüfung einen Fehler
   (Exit-Code ≠ 0): den Inhalt der **Temp-Datei** reparieren (typische Ursache: ein verbliebenes gerades `"` in
   einem Wert — durch die typografische Variante ersetzen, per `Write`/Datei-Lese-Schreib-Zyklus wie in Schritt 3,
   niemals per Shell-Interpolation) und **erneut die Temp-Datei validieren** — diese Schleife wiederholen, bis
   `validate-json.py` auf der Temp-Datei Exit-Code `0` liefert. Existiert `scripts/validate-json.py` im
   Ziel-Projekt-Repo nicht: anlegen (Inhalt siehe Referenz im `agent-flow`-Repo `scripts/validate-json.py` —
   liest `sys.argv[1]`, `json.load`, Exit `0`/`≠0`).
5. **ERST NACH nachweislich validem Parse-Ergebnis: atomar auf den Zielpfad bringen.** Die **validierte**
   Temp-Datei **im selben Verzeichnis** wie `ergebnis_datei` per `mv` (rename) auf `<ergebnis_datei>` verschieben.
   Der Zielpfad erhält damit **ausschließlich bereits geprüften** Inhalt in **einem** atomaren Schritt — ein
   lesender Runner sieht nie eine halbgeschriebene ODER noch ungeprüfte (evtl. ungültige) Fassung.
   **HART: niemals** direkt auf den Zielpfad schreiben und danach reparieren — genau diese Reihenfolge
   (publish-then-fix) ließ den Runner eine ungültige Zwischenfassung lesen (Ursache des Timing-Bugs nach S-061).
   Nach dem `mv` zur Sicherheit noch einmal `validate-json.py <ergebnis_datei>` (muss Exit `0` sein, da bereits
   auf der Temp geprüft).
6. Existiert am Zielpfad bereits eine Datei, wird sie durch den `rename` ersetzt (Überschreiben ist erlaubt
   und erwartet — ein Lauf liefert ein Ergebnis).
7. Fehlt `ergebnis_datei=` im Aufruf → **keine** Datei schreiben, nur die reguläre stdout-Weitergabe
   (Schritt 2 des Hauptablaufs unten) — kein Fehler, reine Rückwärtskompatibilität für den menschlichen
   Direktaufruf. (Kein Validierungslauf nötig, wenn keine Datei geschrieben wird.)

Konventioneller Pfad des Runners (dev-gui S-307, `RegressionDefineRunner`): `board/runs/regression-define/<lauf-id>.json`
im Ziel-Projekt-Repo — bereits durch die bestehende `board/runs/`-Gitignore-Regel abgedeckt
([[feature-batch-orchestration]] AC11), keine eigene Gitignore-Zeile nötig. Die stdout-Prosa/Rückgabe an den
Aufrufer (Schritt 2) bleibt zusätzlich zur Datei bestehen — sie ist für Menschen im Terminal erlaubt, aber
nicht mehr Vertragsgegenstand des headless-Konsumenten (AC12): der Runner liest ausschließlich die Datei.

## 2. Ergebnis

Die Ausgabe des Agenten (Rückgabeformat bei `vorschlag`, Ergebnis-Objekt mit PR-Link/`Abgelehnt:`-Status bei
`uebersetzen`) unverändert an den Aufrufer zurückgeben — der Skill fügt nichts hinzu und kürzt nichts. Ist
`ergebnis_datei=` gesetzt, ist Schritt 1a (Datei-Schreiben) **zusätzlich** zu dieser stdout-Weitergabe
auszuführen, nicht anstelle davon. Der Agent liefert bereits headless-diszipliniert (AC12 der Spec): keine
umschliessende Prosa, keine Rückfrage; der Skill darf diese Disziplin durch eigene Zusätze nicht brechen.
Die stdout-Ausgabe DEINER Session bleibt für den menschlichen Direktaufruf im Terminal wertvoll, ist aber —
seit AC12/AC13 — **nicht mehr der harte Vertrag** für den headless-Konsumenten: dieser liest ausschließlich
die per `ergebnis_datei=` geschriebene Datei (Schritt 1a). Anmerkungen gehören ins `hinweise[]`-Feld des
Formats.

## Grenzen

- Enthält **keine** Test-/Übersetzungslogik, keine Spec-Lese-/Secret-Heuristik-Duplikate — reines Dispatch.
- Schreibt **keinen** Board-Status und keine Board-Felder.
- Erfindet **nie** einen `redigierter_vorschlag`, wenn STDIN in `modus=uebersetzen` fehlt — Ablehnung statt Rätselns.
- Erzwingt **keinen** Resume-Kontext (Lauf 2 bleibt auch ohne `--resume` vollständig funktionsfähig).
- Schreibt **nur** eine `ergebnis_datei`, wenn das Argument explizit gesetzt ist — ohne das Argument keine
  Datei, kein Fehler (Rückwärtskompatibilität, AC13).
- **Kein gerades `"` innerhalb eines JSON-String-Werts** der `ergebnis_datei` — nur typografische
  Anführungszeichen (`„`/`"`, `‚`/`'`) in Textwerten; das gerade `"` ist ausschließlich JSON-Delimiter (AC13).
- Schreibt eine `ergebnis_datei` **nie ohne anschließende Selbstvalidierung** per `scripts/validate-json.py
  <pfad>` (echter JSON-Parser, Datei-Argument, kein interpolierter Shell-String) — bei Fehler reparieren +
  erneut validieren, bis das Ergebnis nachweislich valide parst (AC13).
- **Erstschreib-Schritt der `ergebnis_datei` niemals über einen Shell-Befehl mit interpoliertem Dateiinhalt**
  (kein `echo '…' > datei`, kein Heredoc mit dynamischem Text, kein `python3 -c "…<Text>…"`/`node -e "…<Text>…"`)
  — ausschließlich über das eingebaute `Write`-Werkzeug der Skill-Ausführungsumgebung (AC13, HART).
