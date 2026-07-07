---
name: from-notes
description: Speist einen Obsidian-Notiz-Ordner als dritten Requirement-Weg in den Fabrik-Pfad Konzept -> Spezifikation -> Story ein. Orchestriert drei Stufen IN REIHE — (a) Notiz-Korpus -> docs/concept.md, (b) Konzept -> docs/specs/<feature>.md (+ architekt/dba wo nötig), (c) Spec(s) -> Board-Items/Stories über den bestehenden requirement-Agenten. Ein Fragenkatalog-Gate pro Stufe (genau EIN gesammelter Katalog, am Stück beantwortet; leer -> Auto-Durchlauf), Commit pro Stufe in harter Reihenfolge. Zweiter Modus --sync (Re-Sync, Spec obsidian-sync): gleicht den aktuellen Notiz-Stand gegen docs/concept.md + docs/specs/* ab, meldet Divergenzen als priorisierten Bericht und legt sie als genau EINEN Fragenkatalog (stage sync, je Divergenz uebernehmen/behalten/manuell) vor — schreibt NUR die als uebernehmen gewaehlten Aenderungen, nie automatisch (invertierte Reconcile-Autoritaet); teilt Reader + Katalog-Gate mit dem Ingest und laesst den Reconcile-Vertrag unangetastet (kein Reconcile-Stufe-0). Dritter Modus --audit (read-only): prüft die ID-Kette IDEA->C->Spec->BR->Story->@trace auf Waisen (abwärts/aufwärts) und Widersprüche und gibt einen Ampel-Report aus — ändert nichts. Idea-Roundtrip (Zonen-Modell): Stufe a vergibt stabile IDs (IDEA-NNN je Ideennotiz, C-NNN je Konzeptabschnitt) und stempelt als EINZIGE Vault-Schreiboperation die Frontmatter-Sync-Felder (idea_id, idea_status, last_sync, sync_hash, C-NNN-Referenzen) der übernommenen Notizen; Notiz-Inhalt bleibt unantastbar, gelöscht wird nie (superseded), neue Ideennotizen legt nur reconcile Stufe 3 an. Authoring-only — schreibt NUR docs/, das Profilfeld obsidian_source, Board-Items (To Do) und die genannten Frontmatter-Sync-Felder; KEIN App-Code, KEIN /flow-Start, KEIN Merge/Deploy. Im Ziel-Projekt-Repo ausführen. Aufruf: /agent-flow:from-notes [--cost <mode>] [--sync] [--audit] [<ordnerpfad>].
---

# /agent-flow:from-notes [--cost <mode>] [--sync] [--audit] [<ordnerpfad>]

Speist einen **Obsidian-Notiz-Ordner** (mehrere freie `.md`-Notizen aus der Ideen-/Konzeptphase) als **dritten** Requirement-Weg (neben `new-project`/`init` und `requirement`) in den bestehenden Fabrik-Pfad **Konzept → Spezifikation → Story** ein. cwd = Ziel-Projekt-Repo.

**Dieser Skill ist der einzige Schreiber** der Doc-/Board-/Profil-Änderungen dieses Flusses und orchestriert **drei Stufen in Reihe** — er baut **keinen** eigenen Zerlege-, Schätz- oder Übersetzungs-Baustein neu, sondern **wiederverwendet** die bestehenden Bausteine (Reader, Fragenkatalog-Gate, `requirement`/`architekt`/`dba`).

Bindende Quellen: `docs/specs/obsidian-ingest.md` (AC11–AC22, sowie AC1–AC10 der wiederverwendeten Bausteine) + `docs/architecture/obsidian-ingest-subsystem.md` (§3 Drei-Stufen-Pipeline inkl. ID-Vergabe, §4 `obsidian_source`, §4b Vault-Schreibzonen, §5 Re-Sync, §5a Audit, §6 dev-gui-Schnittstelle). Der **Re-Sync-Modus** (`--sync`) ist ein **eigener Modus dieses Skills** (Spec `docs/specs/obsidian-sync.md`, AC1–AC7, §5 unten); er teilt Reader + Katalog-Gate mit dem Ingest und lässt den Reconcile-Vertrag (`docs/architecture/reconcile-subsystem.md`) **unangetastet**.

> **Authoring-only (AC14, hart) + Zonen-Modell (AC6/AC17).** Die Pipeline schreibt **ausschließlich** durable Docs (`docs/`), das Profilfeld `obsidian_source`, Board-Items (Status **To Do**) und — als **einzige** Vault-Schreiboperation — die **Frontmatter-Sync-Felder** übernommener Ideennotizen (§1.4). **Kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy, **kein** Schreiben ausserhalb dieser Zonen: Notiz-Inhalt ist unantastbar, gelöscht wird nie (`superseded`), neue Ideennotizen legt nur `reconcile` Stufe 3 an (AC18). Item-Status bleibt allein `/flow`-Hoheit.

## Modus-Wahl — Ingest (Default) vs. Re-Sync (`--sync`) (obsidian-sync AC1)

Der Skill hat **drei Modi**:

- **ohne Flag** → **Ingest** (Default): Stufen a→b→c (§0–§4). Notiz **erzeugt** initial Konzept/Spec/Stories.
- **mit `--sync`** → **Re-Sync** (§5, Spec `docs/specs/obsidian-sync.md`): gleicht den **aktuellen Notiz-Stand** gegen den **aktuellen `docs/concept.md` + `docs/specs/*`-Stand** ab, **meldet** Divergenzen und legt sie als **genau EINEN** Fragenkatalog (`stage:"sync"`) vor — schreibt Konzept/Spec **nie** automatisch (invertierte Reconcile-Autorität, obsidian-sync AC3). Tragen Notizen die Sync-Felder aus §1.4, klassifiziert der Bericht jeden Fund per Drei-Wege-Anker (*nur Notiz* / *nur Doku* / *beide geändert = Konflikt*, obsidian-sync AC7).
- **mit `--audit`** → **Integritätsprüfung** (§6, Spec AC19–AC22): **read-only** — prüft die ID-Kette `IDEA → C → Spec → BR → Story → @trace` auf Waisen und Widersprüche, gibt einen Ampel-Report aus, ändert **nichts**.

Die Tokens `--sync` und `--audit` werden — wie `--cost` — **vor** der Ordnerpfad-Auswertung herausgeparst und gehören **nicht** zum Ordnerpfad. `--sync` und `--audit` gleichzeitig → klarer Abbruch (genau ein Modus pro Lauf). Beide Modi teilen sich denselben **Reader** (§0b) und dasselbe **Fragenkatalog-Gate**; der Re-Sync ist ein **eigener Modus** und lässt den **Reconcile-Vertrag** (`docs/architecture/reconcile-subsystem.md`) **unangetastet** — er ist **kein** Reconcile-„Stufe 0" (obsidian-sync AC1). Bei `--sync` gelten **§0** (Setup) und **§0a/§0b** (Ordner + Reader, rein lesend) sinngemäß; die Ingest-Stufen **§1–§3 laufen dann nicht**, stattdessen **§5**. Bei `--audit` gelten **§0/§0a** sinngemäß (Ordner **nur** aus `obsidian_source` — kein Argument nötig, keines wird gesetzt); statt der Stufen läuft **§6**, komplett read-only.

## 0. Setup

- **Cost-Mode auflösen:** Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced` (Kurzformen `low`/`max`/`front` normalisieren; `front`→`frontier`). Beim Task-Dispatch der Agenten (`requirement`/`architekt`/`dba` in Stufe b/c) den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Zeile = Rolle) mitgeben; bei `balanced` **keinen** Override (Agent-Frontmatter gilt). **Ausnahme (Design-Rollen-Pinning, `docs/specs/model-phase-pinning.md` AC3):** der `dba`-Dispatch in Stufe b ist **immer** der **Design-Modus** (Datenmodell-Entwurf → `docs/data-model.md`) — dieser erhält **in jedem Cost-Mode** (auch `low-cost`/`balanced`) einen festen `model: opus`-Override, unabhängig von der `dba`-Matrix-Zeile (die nur den **Review-Modus** des `dba` beschreibt, siehe `knowledge/model-tiers.md` „Design-Rollen-Pinning"). `requirement` (Stufe c) und `architekt` (Stufe b) folgen weiterhin normal der Matrix (dort bereits als Design-Rollen gepinnt). Das `--cost`-Token gehört NICHT zum Ordnerpfad — vor der Argument-Auswertung herausparsen. Ebenso die **`--sync`**/**`--audit`**-Tokens (Modus-Wahl, siehe *Modus-Wahl* oben): vor der Ordnerpfad-Auswertung herausparsen; `--sync` → **Re-Sync** (§5), `--audit` → **Audit** (§6), sonst Ingest.
- **Auth herstellen:** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token, loggt `gh` ein — für Stufe c, die über `requirement` Board-Items anlegt). NICHT `gh auth login --web`.
- **Profil lesen:** `.claude/profile.md` → `default_branch`, `cost_mode`, `obsidian_source` (falls gesetzt).
- **Working-Tree sollte sauber sein**, bevor Stufe a schreibt (sonst vermischen sich fremde Änderungen mit dem Stufen-Commit). Ist der Tree nicht sauber: Hinweis ausgeben, User entscheiden lassen, ob fortgefahren wird.

## 0a. Ordnerpfad auflösen + `obsidian_source` setzen (AC1/AC2 — wiederverwendet, hier nur genutzt)

Precedence **Argument > Profil** (Subsystem §4, Spec AC2):

1. **Ordner-Argument übergeben:** dieses gilt. Als **absoluten** Pfad normalisieren und in `.claude/profile.md` als `obsidian_source: <absoluter-pfad>` setzen/aktualisieren (Feld ist optional/additiv, S-020). War die Zeile im Profil auskommentiert (Vorlagen-Platzhalter `# obsidian_source: …`), wird sie zur aktiven Zeile.
2. **Kein Argument, aber `obsidian_source` im Profil gesetzt:** den Pfad daraus lesen (*deckt A2*).
3. **Weder Argument noch `obsidian_source`:** **klarer Abbruch** mit Meldung „kein Notiz-Ordner angegeben und keiner am Projekt vermerkt" (*deckt E1*, AC2) — **kein** Leerlauf, **keine** leere Pipeline. Ende.

Das Profilfeld-Schreiben ist der **einzige** Profil-Schreibvorgang dieses Skills und fährt mit dem **Stufe-a-Commit** mit (siehe §1.5).

## 0b. Notiz-Korpus lesen (AC4–AC6 — wiederverwendeter Reader, rein lesend)

Den bestehenden **Notiz-Korpus-Reader** aufrufen (S-021, kein Neubau):

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-corpus-read.sh" "<aufgelöster-ordnerpfad>" > "$CORPUS_FILE"
```

- **Exit 0** → `$CORPUS_FILE` hält den konsolidierten Korpus (deterministisch geordnet, je Notiz ein Herkunfts-Marker `===== NOTE: <relativer-pfad> =====`). Weiter mit Stufe a.
- **Exit 2** (Pfad fehlt / kein Verzeichnis / keine `.md`) → **klarer Abbruch** mit der Reader-Meldung (*deckt E2*, AC5); **niemals** eine leere `concept.md`/Spec anlegen. Ende.
- **Exit 1** (Aufruffehler) → Fehler melden, Ende.

`$CORPUS_FILE` ist eine temporäre Datei (`mktemp`), **nie** im Repo committet — der Vault bleibt rein lesend (AC6). Die Herkunfts-Marker im Korpus liefern das `quelle`-Feld für Fragenkatalog-Einträge (AC9).

## 1. Stufe a — Notiz-Korpus → `docs/concept.md` (AC11a, kritischste Stufe)

**Ziel:** den Notiz-Korpus zum Konzept konsolidieren (Problem · Nutzer · Ziele · Nicht-Ziele · Scope). Diese Stufe ist der **kritische Punkt** (Subsystem §1/§3): eine ungenaue Erst-Übersetzung vererbt Fehler an Spec und Stories.

1. **Übersetzen (niedrigste Nachfrage-Schwelle, AC10):** Aus `$CORPUS_FILE` das Konzept nach `docs/concept.md` schreiben (Skelett `templates/_docs/concept.md`; existiert bereits ein Root-`CONCEPT.md`-Layout wie in manchen Projekten, dort die betroffenen Sektionen ergänzen statt einer neuen Datei — dieselbe Layout-Konvention wie `reconcile`). **Jede** relevante Mehrdeutigkeit/jeder Widerspruch im Ideen-Text wird zur **Frage** (Fragenkatalog-Eintrag), **nicht** zur stillen Annahme — die Schwelle ist hier bewusst niedrig (AC10). Jeder Katalog-Eintrag trägt im `quelle`-Feld den Herkunfts-Marker der Quellnotiz.
2. **Fragenkatalog-Gate (AC7/AC8/AC9):** Alle offenen Punkte dieser Stufe **gesammelt** als **genau EINE** JSON-Liste von Frage-Objekten aufbauen — je Objekt `stage:"a"`, `id` (katalog-eindeutig, Muster `a-<n>`), `frage`, `quelle` (Notiz-Fundstelle), optional `optionen[]` (Format-Vertrag: `board/fragenkatalog.schema.json`). Den Katalog durch den wiederverwendeten Gate-Validator prüfen und das Vorlege-Verhalten am stdout-Token festmachen:
   ```bash
   printf '%s' "$KATALOG_A_JSON" | bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-fragenkatalog-validate.sh"
   ```
   - **`empty`** → keine offenen Fragen → **Auto-Durchlauf** (AC8): kein Katalog vorlegen, direkt zu 1.3 (ID-Kette).
   - **`valid`** → nicht-leerer Katalog → dem User **am Stück** vorlegen (AC7): im Terminal-Pfad via `AskUserQuestion` (ein Prompt, alle Fragen zusammen); im dev-gui-Pfad rendert dev-gui denselben JSON-Katalog und reicht die Antworten über die `id`-Zuordnung zurück (AC9). **Erst nach** vollständiger Beantwortung fließen die Antworten in `docs/concept.md` ein.
   - **Exit 1/2** (Vertragsverletzung / Aufrufproblem) → den selbst erzeugten Katalog korrigieren und erneut validieren (nie einen ungültigen Katalog vorlegen).
3. **ID-Kette verankern (AC15/AC16):** Nach beantwortetem (oder leerem) Katalog die Kette ID-fest machen:
   - **`IDEA-NNN` je Quellnotiz:** Notizen, deren Frontmatter bereits eine `idea_id` trägt, behalten sie **unverändert** (Re-Ingest vergibt nie neu, AC15). Für Notizen **ohne** `idea_id`: die nächste freie Nummer bestimmen — höchste existierende `IDEA-NNN` über einen Frontmatter-Scan **aller** `.md` des `obsidian_source`-Ordners ermitteln (`grep -rh '^idea_id:' …`), +1 fortlaufend; Nummern werden **nie** wiederverwendet.
   - **Ausnahme parked/rejected (AC18):** Notizen mit `idea_status: parked | rejected` fließen **nicht** (erneut) ins Konzept — bewusste Entscheidung, keine Lücke; sie erhalten weder neue Anker noch einen neuen Stempel.
   - **`C-NNN` je Konzeptabschnitt:** jeder in Schritt 1 erzeugte/geänderte Abschnitt in `docs/concept.md` erhält eine stabile ID `C-NNN` mit Herkunftsvermerk `(← IDEA-NNN)` in der Abschnittsüberschrift (Nummern fortlaufend über die höchste existierende `C-NNN` der Datei hinaus, nie wiederverwendet). Stufe b referenziert später je Spec die Konzept-Herkunft `(← C-NNN)` (AC16).
4. **Frontmatter-Stempel (AC17/AC18 — die EINZIGE Vault-Schreiboperation):** Für jede übernommene Quellnotiz **ausschließlich** im YAML-Frontmatter die Sync-Felder setzen/aktualisieren — sonst **nichts** an der Datei anfassen:
   ```yaml
   idea_id: IDEA-NNN
   idea_status: adopted
   last_sync: <ISO-Zeitstempel>
   sync_hash: <sha256 des Notiz-Inhalts zum Übernahme-Zeitpunkt>
   c_refs: [C-NNN, …]
   ```
   Kein anderes Frontmatter-Feld, **kein** Notiz-Inhalt wird verändert; **nie** eine Notiz gelöscht oder neu angelegt (Überholtes → nur `idea_status: superseded`; neue Ideennotizen sind allein `reconcile`-Stufe-3-Sache, AC18). Der Vault wird **nie** ge-`add`et/committet — der Stempel ist eine reine Dateisystem-Änderung im externen Ordner (AC6). `sync_hash` = Hash des Notiz-**Inhalts** (Body ohne die Sync-Felder selbst), damit spätere Läufe (Re-Sync AC7, `reconcile` Stufe 3) den Drei-Wege-Abgleich rechnen können.
5. **Commit Stufe a (AC12, durable):** Erst **nachdem** Katalog, Anker und Stempel abgeschlossen sind:
   ```bash
   git add docs/concept.md .claude/profile.md && git commit -m "notes(a): Notiz-Korpus -> docs/concept.md (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Der Profilfeld-Diff (`obsidian_source`, §0a) fährt hier mit. `.claude/profile.md` nur `git add`en, wenn §0a das Feld tatsächlich gesetzt/geändert hat. Lehnt Branch-Protection den Direkt-Push ab → docs-only-PR öffnen + selbst mergen (analog `requirement`-Skill). Der Notiz-Ordner wird **nie** ge-`add`et (AC6/AC14).

Stufe b startet **erst nach** committetem Stufe-a-Ergebnis (harte Reihenfolge, AC12).

## 2. Stufe b — `docs/concept.md` → `docs/specs/<feature>.md` (AC11b/AC13)

**Ziel:** je Capability des Konzepts **eine** durable Spec ableiten, den bestehenden **Spec-Vertrag wiederverwenden** (AC13) — Vorlage, `spec_format`-Stempel, nummerierte AC, Traceability.

1. **Spec(s) schreiben:** je Capability eine `docs/specs/<feature-slug>.md` aus `templates/_docs/specs/_template.md` — Zweck, Verhalten, **nummerierte Acceptance-Kriterien (AC1, AC2, …)**, Verträge, Edge-Cases, NFRs, Nicht-Ziele. **`spec_format`-Stempel:** den Wert 1:1 aus der **aktuellen** `_template.md` übernehmen (nicht hartkodieren), wie es der Spec-Vertrag (`docs/specs/spec-format-field.md` AC3) und `requirement` fordern. **Konzept-Herkunft:** jede Spec referenziert ihre `C-NNN`-Herkunft `(← C-NNN)` (AC16).
2. **Tiefes Detail via bestehende Agenten (AC11b/AC13 — kein Neubau):** Wo tiefes Architektur-Detail nötig ist, den **`architekt`**-Agenten (Task) dispatchen → `docs/architecture.md` bzw. `docs/architecture/<subsystem>.md`. Wo ein Datenmodell nötig ist, den **`dba`**-Agenten (Task, **Design-Modus**) → `docs/data-model.md` — dieser Dispatch bekommt **immer** `model: opus` (Design-Rollen-Pinning, siehe §0), unabhängig vom aktiven Cost-Mode. Beide schreiben nur in den Working-Tree (kein Commit) — das Committen macht dieser Skill in 2.4.
3. **Fragenkatalog-Gate (AC7/AC8/AC9):** identische Mechanik wie 1.2, aber `stage:"b"`, `id`-Muster `b-<n>`, `quelle` = Konzept-/Doku-Fundstelle. `empty` → Auto-Durchlauf; `valid` → dem User am Stück vorlegen (`AskUserQuestion` / dev-gui); erst nach Beantwortung fließen die Antworten in die Spec(s)/Architektur ein.
4. **Commit Stufe b (AC12):** Erst nach beantwortetem/leerem Katalog:
   ```bash
   git add docs/ && git commit -m "notes(b): Konzept -> docs/specs/<…> (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Alle in dieser Stufe berührten `docs/`-Dateien (Spec(s) + ggf. `architecture*.md`/`data-model.md`) fahren in **einem** Stufe-b-Commit. Branch-Protection → docs-only-PR + Self-Merge.

Stufe c startet **erst nach** committetem Stufe-b-Ergebnis (harte Reihenfolge, AC12).

## 3. Stufe c — Spec(s) → Board-Items/Stories über den `requirement`-Agenten (AC11c/AC13)

**Ziel:** die in Stufe b entstandenen Spec(s) in Board-Items/Stories zerlegen — **über den bestehenden `requirement`-Agenten** (AC11: „kein zweiter Zerlege-Pfad").

1. **`requirement`-Agent dispatchen (Task, `agents/requirement.md`):** als Eingabe die in Stufe b geschriebene(n) Spec(s) übergeben — nicht eine neue vage Anforderung, sondern der Verweis auf die bereits durable Spec(s) mit dem Auftrag, sie in Board-Items zu zerlegen. Der `requirement`-Agent leistet dabei **ohnehin** (AC13):
   - Zerlegung in TODOs (je Item ≈ ein coder→reviewer→tester-Durchlauf),
   - je Item ein Board-Item (**To Do**), das auf **Spec + AC-Nummern** zeigt (**kein** eingebetteter AC-Text),
   - die **A-priori-Schätzung** (`size_est`/`dispo_est`/`confidence`/`estimate_note`) bei der Anlage.

   Da die Spec(s) bereits geschrieben sind, sollte der `requirement`-Agent hier i.d.R. **nicht** erneut Spec-schreiben — sein Fokus ist die Zerlegung. Legt er dabei doch Spec-Feinschliff nach (Working-Tree), fährt der in den Stufe-c-Commit (3.3).
2. **Fragenkatalog-Gate (AC7/AC8/AC9):** Bleiben bei der Zerlegung Unklarheiten offen (z.B. Schnitt-Granularität, Priorität, Abhängigkeiten), diese **gesammelt** als **einen** Katalog `stage:"c"` (`id`-Muster `c-<n>`, `quelle` = Spec-/Doku-Fundstelle) — Validator + Vorlege-Verhalten wie oben. Der `requirement`-Agent stellt seine eigenen gezielten Rückfragen normalerweise selbst; ein separater Stufe-c-Katalog wird nur aufgebaut, wenn nach seinem Lauf noch pipeline-seitige Unklarheiten offen sind (kein leerer Katalog, AC8).
3. **Commit Stufe c (AC12):** Der `requirement`-Agent legt die Board-Items an (Status **To Do**, `/flow`-Hoheit endet dort — kein Status-Vorschub, AC14). Etwaige vom Agenten in den Working-Tree geschriebene `docs/`-Deltas dieser Stufe committen:
   ```bash
   git add docs/ && git commit -m "notes(c): Spec(s) -> Board-Items (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Gibt es keinen `docs/`-Delta in Stufe c (Items liegen im File-Board bzw. via `gh` am GitHub-Board), entfällt der Doc-Commit — die Board-Items selbst sind der durable Zustand dieser Stufe.

**Kein `/flow`-Start, kein Merge/Deploy** (AC14). Ausser den Frontmatter-Stempeln (§1.4) bleibt der Ordner unangetastet; das Projekt kann jederzeit erneut aus den Notizen arbeiten (Re-Ingest, `[[obsidian-sync]]` oder `--audit`).

## 4. Output

```
Obsidian-Ingest (from-notes) — Ordner: <aufgelöster-pfad> (Quelle: <Argument | Profil obsidian_source>)
Korpus: <n> Notiz(en) gelesen (<p> parked/rejected übersprungen)
Stufe a: docs/concept.md geschrieben — Katalog a: <leer/Auto-Durchlauf | <k> Frage(n) beantwortet> — IDs: <IDEA-… neu/bestehend -> C-…> — <q> Notiz(en) gestempelt (adopted) — committet <sha|PR>
Stufe b: docs/specs/<…> (+ <architektur/data-model falls>) — Katalog b: <…> — committet <sha|PR>
Stufe c: <m> Board-Item(s) (To Do) via requirement — Katalog c: <…> — committet <sha|PR|kein Doc-Delta>
  #<id> <title> — Spec <feature-slug> (AC<…>) — size_est: <…> dispo_est: <…>
Bereit für /agent-flow:flow.
```

## 5. Re-Sync-Modus (`--sync`) — Notiz ↔ Konzept/Spec abgleichen (obsidian-sync AC1–AC7)

**Nur bei `--sync`** (statt der Ingest-Stufen §1–§3). Bindende Quelle: `docs/specs/obsidian-sync.md` (AC1–AC7) + `docs/architecture/obsidian-ingest-subsystem.md` §5. Dieser Modus **erkennt und meldet** Widersprüche zwischen dem **aktuellen Notiz-Stand** und dem **aktuellen `docs/concept.md` + `docs/specs/*`-Stand** und legt sie dem User **zur Entscheidung** vor — er **überschreibt Konzept/Spec nie automatisch** (invertierte Reconcile-Autorität, AC3). Er teilt Reader (§0b) + Fragenkatalog-Gate mit dem Ingest, ist aber ein **eigener Modus** und lässt den **Reconcile-Vertrag** (`docs/architecture/reconcile-subsystem.md`) **unangetastet** (AC1) — **kein** Reconcile-„Stufe 0".

### 5.1 Vergleichsseiten beschaffen (AC1, rein lesend)

1. **Ordner auflösen** (Precedence wie §0a: Argument > `obsidian_source`): der Re-Sync läuft im Normalfall **ohne** Ordner-Argument → `obsidian_source` aus `.claude/profile.md`. Fehlt `obsidian_source` **und** kein Argument → **klarer Abbruch** „kein Notiz-Ordner am Projekt vermerkt" (AC6, *deckt E1*). Ende — **kein** Leerlauf, **keine** Doku-Änderung. Der Re-Sync schreibt `obsidian_source` **nicht** neu (nur der Ingest bei explizitem Argument, §0a).
2. **Notiz-Korpus lesen (linke Vergleichsseite)** — derselbe Reader wie §0b (kein Neubau, AC1):
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-corpus-read.sh" "<aufgelöster-ordnerpfad>" > "$CORPUS_FILE"
   ```
   - **Exit 2** (Ordner unlesbar / keine `.md`) → **klarer Abbruch** mit der Reader-Meldung (AC6, *deckt E1*), **niemals** eine Doku-Änderung. Ende.
   - **Exit 0** → `$CORPUS_FILE` (`mktemp`, **nie** committet — AC6) hält den Korpus; die Herkunfts-Marker `===== NOTE: <pfad> =====` liefern das `notiz_fundstelle`-/`quelle`-Feld.
3. **Doku-Stand lesen (rechte Vergleichsseite)** — der **aktuelle** `docs/concept.md` **+ alle** `docs/specs/*`, **rein lesend**.

### 5.2 Divergenzen erkennen + priorisierter Bericht (AC2 — reiner Bericht, kein Gate)

Beide Seiten abgleichen und **Divergenzen** sammeln. Je Fund **genau diese Felder** (Bericht-Format, Vertrag der Spec):

- **`notiz_fundstelle`** — relativer Notiz-Pfad (Herkunfts-Marker) + Kontext,
- **`doku_ziel`** — betroffenes Doku-**Dokument + Sektion** (z.B. `docs/concept.md §Ziele`, `docs/specs/<feature>.md §AC3`),
- **`divergenz_art`** — Art der Divergenz, z.B. *Notiz widerspricht Konzept-Aussage* · *Notiz enthält Neues, das die Spec nicht abbildet* · *Doku enthält, was die Notiz nicht mehr trägt*,
- **`richtungsvorschlag`** — unverbindlicher Vorschlag, welche Richtung plausibel ist.

**Drei-Wege-Anker (obsidian-sync AC7):** Trägt eine Notiz die Sync-Felder `last_sync`/`sync_hash` (Stempel aus Ingest §1.4 bzw. `reconcile` Stufe 3), wird jeder Fund zusätzlich **klassifiziert**: *nur Notiz geändert* (Notiz-Hash ≠ `sync_hash`, Doku seit `last_sync` unverändert) · *nur Doku geändert* · *beide geändert* (**echter Konflikt** — im Bericht priorisiert und als solcher gekennzeichnet). Fehlen die Felder → Vergleich wie bisher rein inhaltlich, **kein** Regress; die Autorität ändert sich durch die Klassifikation **nicht** (nie automatisch schreiben).

Der Bericht ist **priorisiert** (Konflikte/klarste Widersprüche zuerst) und **rein informativ**: **kein** Gate, **keine** automatischen Board-Items, **kein** `/flow`-Start (AC2/AC6). Widerspricht ein Notiz-Stand **mehreren** Doku-Stellen → **mehrere Funde**, aber in **einem** Bericht/Katalog (nie verstreute Einzel-Prompts).

### 5.3 Deckungsgleich → Ende ohne Katalog/Änderung (AC5, *deckt A1*)

Findet 5.2 **keine** Divergenz → **kein** Fragenkatalog, **keine** Doku-Änderung. Klare **„deckungsgleich"**-Meldung ausgeben und **enden** (Rauscharmut, AC5). Der Notiz-Ordner bleibt unangetastet.

### 5.4 Genau EIN Fragenkatalog, gerichteter Entscheid (AC4)

Bei ≥1 Divergenz **alle** als **genau EINEN** Fragenkatalog aufbauen — gleiches maschinenlesbares Rückgabeformat wie `[[obsidian-ingest]]` AC9 (`board/fragenkatalog.schema.json`), je Frage: `stage:"sync"`, `id`-Muster `sync-<n>` (katalog-eindeutig), `frage` (die Divergenz in Alltagssprache), `quelle` = `notiz_fundstelle` + `doku_ziel`, und `optionen:["uebernehmen","behalten","manuell"]` (je Divergenz **eine** Frage mit genau diesen drei Richtungen). Den Katalog durch den **wiederverwendeten** Gate-Validator prüfen:
   ```bash
   printf '%s' "$KATALOG_SYNC_JSON" | bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-fragenkatalog-validate.sh"
   ```
   - **`valid`** → dem User **am Stück** vorlegen (Terminal: `AskUserQuestion`, ein Prompt für alle Divergenzen; dev-gui rendert denselben JSON-Katalog und reicht die Antworten über die `id`-Zuordnung zurück). **Nie** Einzel-Prompt je Fund verstreut (AC4/Edge).
   - **`empty`** darf hier **nicht** auftreten (bei ≥1 Divergenz ist der Katalog nicht leer); erscheint es doch → es lag Deckungsgleichheit vor → 5.3.
   - **Exit 1/2** (Vertragsverletzung / Aufrufproblem) → den selbst erzeugten Katalog korrigieren und erneut validieren (nie einen ungültigen Katalog vorlegen).

### 5.5 Selektiv schreiben — nur „übernehmen" (AC3/AC4, *deckt A2*)

Erst **nach** vollständiger Beantwortung, **je Divergenz** streng nach Entscheid:

- **`uebernehmen`** → die Notiz-Aussage in das jeweilige `doku_ziel` (`docs/concept.md` bzw. `docs/specs/<feature>.md`) **schreiben**.
- **`behalten`** → **nichts** ändern; die bestehende `concept.md`/Spec bleibt unverändert (*deckt A2*).
- **`manuell`** → **nichts** automatisch ändern; als offener Punkt dem User überlassen.

**Schreib-Umfang (hart, AC3/AC4):** ausschließlich `docs/concept.md` / `docs/specs/*` und **ausschließlich** die als „übernehmen" gewählten Divergenzen — **nie** automatisch, **nie** in den Notiz-Ordner (AC6). Jede geschriebene Änderung ist auf eine `notiz_fundstelle` + einen expliziten User-Entscheid rückführbar (NFR Nachvollziehbarkeit). Gibt es ≥1 „übernehmen", fahren die Änderungen in **einen** durable Commit (`docs/`); Branch-Protection → docs-only-PR + Self-Merge (analog Ingest §1.5).

### 5.6 Kein Folge-Automatismus (AC6)

Der Re-Sync startet **kein** `/flow` und legt **keine** Stories automatisch an — neue Stories entstehen bewusst nur über den Ingest-Stufe-c- bzw. den regulären `requirement`-Fluss. Der Notiz-Ordner wird **nie** beschrieben, verschoben oder ge-`add`et.

### 5.7 Output (Re-Sync)

```
Obsidian-Re-Sync (from-notes --sync) — Ordner: <aufgelöster-pfad> (Quelle: obsidian_source)
Korpus: <n> Notiz(en) gelesen · Vergleich gegen docs/concept.md + docs/specs/*
Divergenzen: <k gefunden | 0 -> deckungsgleich, keine Änderung>
  [P<i>] <notiz_fundstelle> -> <doku_ziel> : <divergenz_art> <(Drei-Wege: nur-notiz|nur-doku|KONFLIKT)> (Vorschlag: <richtungsvorschlag>)
Katalog sync: <k Frage(n) beantwortet | -> deckungsgleich, kein Katalog>
Geschrieben: <übernommene Divergenz(en) in docs/… -> commit <sha|PR> | keine (alles behalten/manuell)>
Kein /flow-Start, keine Story-Anlage, kein Schreiben in den Notiz-Ordner.
```

## 6. Audit-Modus (`--audit`) — Integritätsprüfung der ID-Kette (AC19–AC22, read-only)

Prüft die gesamte Kette `IDEA-NNN → C-NNN → Spec → BR → Story → @trace` auf Lücken und Widersprüche. **Ändert nichts** — weder Vault noch `docs/` noch Board noch Profil (AC19). Kein Fragenkatalog, kein Commit, kein PR.

### 6.1 Quellen einsammeln (abgeleitet, nie handgepflegt — AC20)
Je Lauf **frisch** berechnen; es gibt **keine** persistierte Map-Datei als Wahrheit:
1. **Vault-Seite:** Frontmatter-Scan aller `.md` unter `obsidian_source` (fehlt das Feld im Profil → klarer Abbruch „kein Notiz-Ordner am Projekt vermerkt", analog E1) → je Notiz `idea_id`, `idea_status`, `c_refs`, `last_sync`, `sync_hash`.
2. **Repo-Seite:** `docs/concept.md` → alle `C-NNN`-Anker + deren `(← IDEA-NNN)`-Herkunft; `docs/specs/*.md` → Spec-IDs + `(← C-NNN)`-Herkunft + referenzierte `BR-NNN`.
3. **Bestehende Traceability:** die abgeleitete Spec↔Test-Map des Traceability-Subsystems (Board-Items → Spec-ID, `@trace <slug>#AC/BR` im Testcode) **wiederverwenden** — kein zweiter Scanner für die untere Ketten-Hälfte.

### 6.2 Klassifizieren (AC21)
- **Waisen abwärts:** Idee (`adopted`) ohne `C-NNN` · `C-NNN` ohne Spec-Referenz · Spec ohne Board-Item/Test.
- **Waisen aufwärts:** Spec/`C-NNN` ohne Ideen-Herkunft — typisch nach Code-first; diese Liste ist der Input für `reconcile` Stufe 3 (AC19 dort).
- **Widersprüche:** `superseded`-Idee wird noch referenziert · `c_refs`/Spec zeigt auf nicht existente `C-NNN` · doppelt vergebene IDs.
- `idea_status: parked | rejected` = **bewusste Entscheidung**, wird **nicht** als Lücke gemeldet.

### 6.3 Report (AC22)
Terminal: **Ampel je Kette** — 🟢 durchgängig · 🟡 Lücke (Waise) · 🔴 Widerspruch — plus Zusammenfassung (Ketten gesamt/grün/gelb/rot). Zusätzlich **maschinenlesbar** (dev-gui-Schnittstelle, ohne agent-flow-Änderung andockbar): JSON-Fund-Liste analog Fragenkatalog-Feldmuster — je Fund `{ id, kette (IDEA/C/Spec-Bezug), klasse (waise-abwaerts|waise-aufwaerts|widerspruch), fundstelle }`.

### 6.4 Output (Audit)
```
Obsidian-Audit (from-notes --audit) — Ordner: <obsidian_source>
Ketten: <n> gesamt — <g> 🟢 · <y> 🟡 · <r> 🔴
🟡 Waisen abwärts: <IDEA-… ohne C | C-… ohne Spec | Spec <slug> ohne Item/Test>, …
🟡 Waisen aufwärts (Input für reconcile Stufe 3): <C-…/Spec <slug> ohne Ideen-Herkunft>, …
🔴 Widersprüche: <…>, …
parked/rejected (Entscheidung, keine Lücke): <IDEA-…>, …
Read-only — nichts geändert.
```

## Grenzen (HART)

- **Authoring-only (AC14):** editiert/erzeugt **ausschließlich** `docs/`, `.claude/profile.md` (nur `obsidian_source`), Board-Items (**To Do**) und die Frontmatter-Sync-Felder (§1.4) — **kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy, **kein** Item-Status jenseits „To Do" (das ist `/flow`-Hoheit).
- **Vault-Zonen-Modell (AC6/AC17/AC18):** im Obsidian-Ordner werden **ausschließlich** die Frontmatter-Sync-Felder übernommener Notizen gestempelt (§1.4) — **kein** Notiz-Inhalt, **kein** Löschen (`superseded` statt Löschen), **kein** Anlegen neuer Notizen (nur `reconcile` Stufe 3), **nie** verschoben oder ge-`add`et/committet. Alles andere schreibt nur in `docs/`, `.claude/profile.md` und das Board.
- **Audit ist read-only (AC19):** `--audit` ändert **nichts** — kein Vault-Stempel, kein Doc, kein Board, kein Profil; Coverage-Map je Lauf frisch abgeleitet, nie persistiert (AC20).
- **Kein zweiter Zerlege-/Schätz-/Übersetzungs-Pfad (AC11/AC13):** Reader (S-021), Fragenkatalog-Gate (S-022), Spec-Vertrag/Vorlage, `requirement` (Zerlegung + Schätzung), `architekt`/`dba` (tiefes Detail) werden **wiederverwendet**, nicht dupliziert.
- **Commit pro Stufe, harte Reihenfolge (AC12):** jede Stufe wird **einzeln** committet, **nachdem** ihr Fragenkatalog beantwortet (oder leer) ist — **nicht** am Ende in einem Rutsch. b startet erst nach committetem a, c erst nach committetem b. Zwischenstände sind durable, der Lauf ist jederzeit fortsetzbar.
- **Genau EIN gesammelter Katalog pro Stufe (AC7), leer → Auto-Durchlauf (AC8):** nie einzeln pro Unklarheit sofort erfragen; nie einen leeren Katalog vorlegen. Das Vorlege-Verhalten entscheidet ausschließlich das stdout-Token des Gate-Validators (`empty` vs. `valid`).
- **Re-Sync (`--sync`) — kein Blind-Overwrite, invertierte Reconcile-Autorität (obsidian-sync AC1/AC3/AC6):** der Re-Sync-Modus (§5) überschreibt Konzept/Spec **nie** automatisch; jede Divergenz ist ein per-Fund-User-Entscheid (`uebernehmen`/`behalten`/`manuell`), und **nur** `uebernehmen` schreibt — ausschließlich nach `docs/concept.md`/`docs/specs/*`, nie in den Notiz-Ordner. Er ist ein **eigener Modus** desselben Skills, teilt Reader + Katalog-Gate mit dem Ingest und lässt den **Reconcile-Vertrag unangetastet** (kein Reconcile-„Stufe 0"). **Kein** `/flow`-Start, **keine** automatische Story-Anlage. Bei Deckungsgleichheit: **kein** Katalog, **keine** Änderung, „deckungsgleich"-Meldung.
