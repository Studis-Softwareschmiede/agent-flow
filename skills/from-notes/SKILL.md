---
name: from-notes
description: Speist einen Obsidian-Notiz-Ordner als dritten Requirement-Weg in den Fabrik-Pfad Konzept -> Spezifikation -> Story ein. Orchestriert drei Stufen IN REIHE — (a) Notiz-Korpus -> docs/concept.md, (b) Konzept -> docs/specs/<feature>.md (+ architekt/dba wo nötig), (c) Spec(s) -> Board-Items/Stories über den bestehenden requirement-Agenten. Ein Fragenkatalog-Gate pro Stufe (genau EIN gesammelter Katalog, am Stück beantwortet; leer -> Auto-Durchlauf), Commit pro Stufe in harter Reihenfolge. Zweiter Modus --sync (Re-Sync, Spec obsidian-sync): gleicht den aktuellen Notiz-Stand gegen docs/concept.md + docs/specs/* ab, meldet Divergenzen als priorisierten Bericht und legt sie als genau EINEN Fragenkatalog (stage sync, je Divergenz uebernehmen/behalten/manuell) vor — schreibt NUR die als uebernehmen gewaehlten Aenderungen, nie automatisch (invertierte Reconcile-Autoritaet); teilt Reader + Katalog-Gate mit dem Ingest und laesst den Reconcile-Vertrag unangetastet (kein Reconcile-Stufe-0). Dritter Modus --audit (read-only): prüft die ID-Kette IDEA->C->Spec->BR->Story->@trace auf Waisen (abwärts/aufwärts) und Widersprüche und gibt einen Ampel-Report aus — ändert nichts. Idea-Roundtrip (Zonen-Modell): Stufe a vergibt stabile IDs (IDEA-NNN je Ideennotiz, C-NNN je Konzeptabschnitt) und stempelt als EINZIGE Vault-Schreiboperation die Frontmatter-Sync-Felder (idea_id, idea_status, last_sync, sync_hash, C-NNN-Referenzen) der übernommenen Notizen; Notiz-Inhalt bleibt unantastbar, gelöscht wird nie (superseded), neue Ideennotizen legt nur reconcile Stufe 3 an. Authoring-only — schreibt NUR docs/, das Profilfeld obsidian_source, Board-Items (To Do) und die genannten Frontmatter-Sync-Felder; KEIN App-Code, KEIN /flow-Start, KEIN Merge/Deploy. Headless-Signal --gui (AC23-AC25): schaltet die Fragenkatalog-Gates von interaktivem AskUserQuestion auf JSON-Endausgabe um — jede Runde (initial + Resume) endet mit genau EINEM JSON-Objekt als letzter Ausgabe ({status:needs-answers,catalog:[…]} bzw. {status:done}), damit der dev-gui-ObsidianIngestRunner das Runden-Ende maschinenlesbar erkennt; ohne --gui bleibt das interaktive Verhalten unveraendert. Im Ziel-Projekt-Repo ausführen. Aufruf: /agent-flow:from-notes [--gui] [--cost <mode>] [--sync] [--audit] [<ordnerpfad>].
---

# /agent-flow:from-notes [--gui] [--cost <mode>] [--sync] [--audit] [<ordnerpfad>]

Speist einen **Obsidian-Notiz-Ordner** (mehrere freie `.md`-Notizen aus der Ideen-/Konzeptphase) als **dritten** Requirement-Weg (neben `new-project`/`init` und `requirement`) in den bestehenden Fabrik-Pfad **Konzept → Spezifikation → Story** ein. cwd = Ziel-Projekt-Repo.

**Dieser Skill ist der einzige Schreiber** der Doc-/Board-/Profil-Änderungen dieses Flusses und orchestriert **drei Stufen in Reihe** — er baut **keinen** eigenen Zerlege-, Schätz- oder Übersetzungs-Baustein neu, sondern **wiederverwendet** die bestehenden Bausteine (Reader, Fragenkatalog-Gate, `requirement`/`architekt`/`dba`).

Bindende Quellen: `docs/specs/obsidian-ingest.md` (AC11–AC22, sowie AC1–AC10 der wiederverwendeten Bausteine) + `docs/architecture/obsidian-ingest-subsystem.md` (§3 Drei-Stufen-Pipeline inkl. ID-Vergabe, §4 `obsidian_source`, §4b Vault-Schreibzonen, §5 Re-Sync, §5a Audit, §6 dev-gui-Schnittstelle). Der **Re-Sync-Modus** (`--sync`) ist ein **eigener Modus dieses Skills** (Spec `docs/specs/obsidian-sync.md`, AC1–AC7, §5 unten); er teilt Reader + Katalog-Gate mit dem Ingest und lässt den Reconcile-Vertrag (`docs/architecture/reconcile-subsystem.md`) **unangetastet**. **PM-Import** (Spec `docs/specs/pm-import.md`, AC1–AC10 implementiert): erweitert Stufe a/b/c um einen deterministischen Erkennungs- und Mapping-Pfad für pm-skills-Artefakte (§0c); Idempotenz, ID-Kette und Drift-Erkennung für PM-Quellen (AC6/AC7/AC10) laufen **ohne Sonderfall** über die bestehende Ideen-Pipeline-Mechanik (§0d) — keine neue Pipeline, kein neuer Vault-Schreibpfad, Reader/Gates/ID-Kette unverändert.

> **Authoring-only (AC14, hart) + Zonen-Modell (AC6/AC17).** Die Pipeline schreibt **ausschließlich** durable Docs (`docs/`), das Profilfeld `obsidian_source`, Board-Items (Status **To Do**) und — als **einzige** Vault-Schreiboperation — die **Frontmatter-Sync-Felder** übernommener Ideennotizen (§1.4). **Kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy, **kein** Schreiben ausserhalb dieser Zonen: Notiz-Inhalt ist unantastbar, gelöscht wird nie (`superseded`), neue Ideennotizen legt nur `reconcile` Stufe 3 an (AC18). Item-Status bleibt allein `/flow`-Hoheit.

## Modus-Wahl — Ingest (Default) vs. Re-Sync (`--sync`) (obsidian-sync AC1)

Der Skill hat **drei Modi**:

- **ohne Flag** → **Ingest** (Default): Stufen a→b→c (§0–§4). Notiz **erzeugt** initial Konzept/Spec/Stories.
- **mit `--sync`** → **Re-Sync** (§5, Spec `docs/specs/obsidian-sync.md`): gleicht den **aktuellen Notiz-Stand** gegen den **aktuellen `docs/concept.md` + `docs/specs/*`-Stand** ab, **meldet** Divergenzen und legt sie als **genau EINEN** Fragenkatalog (`stage:"sync"`) vor — schreibt Konzept/Spec **nie** automatisch (invertierte Reconcile-Autorität, obsidian-sync AC3). Tragen Notizen die Sync-Felder aus §1.4, klassifiziert der Bericht jeden Fund per Drei-Wege-Anker (*nur Notiz* / *nur Doku* / *beide geändert = Konflikt*, obsidian-sync AC7).
- **mit `--audit`** → **Integritätsprüfung** (§6, Spec AC19–AC22): **read-only** — prüft die ID-Kette `IDEA → C → Spec → BR → Story → @trace` auf Waisen und Widersprüche, gibt einen Ampel-Report aus, ändert **nichts**.

Die Tokens `--gui`, `--sync` und `--audit` werden — wie `--cost` — **vor** der Ordnerpfad-Auswertung herausgeparst und gehören **nicht** zum Ordnerpfad. `--sync` und `--audit` gleichzeitig → klarer Abbruch (genau ein Modus pro Lauf). `--gui` ist **orthogonal** zur Modus-Wahl (Ingest/Re-Sync) und schaltet nur den **Ausgabekanal** des Fragenkatalog-Gates auf Headless-JSON um (§0c-headless + Gate-Punkte §1.2/§2.3/§3.2/§5.4) — siehe **Headless-Modus** unten. Beide Modi teilen sich denselben **Reader** (§0b) und dasselbe **Fragenkatalog-Gate**; der Re-Sync ist ein **eigener Modus** und lässt den **Reconcile-Vertrag** (`docs/architecture/reconcile-subsystem.md`) **unangetastet** — er ist **kein** Reconcile-„Stufe 0" (obsidian-sync AC1). Bei `--sync` gelten **§0** (Setup) und **§0a/§0b** (Ordner + Reader, rein lesend) sinngemäß; die Ingest-Stufen **§1–§3 laufen dann nicht**, stattdessen **§5**. Bei `--audit` gelten **§0/§0a** sinngemäß (Ordner **nur** aus `obsidian_source` — kein Argument nötig, keines wird gesetzt); statt der Stufen läuft **§6**, komplett read-only.

## 0. Setup

- **Cost-Mode auflösen:** Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced` (Kurzformen `low`/`max`/`front` normalisieren; `front`→`frontier`). Beim Task-Dispatch der Agenten (`requirement`/`architekt`/`dba`/`designer` in Stufe b/c) den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Zeile = Rolle) mitgeben; bei `balanced` **keinen** Override (Agent-Frontmatter gilt). **Ausnahme (Design-Rollen-Pinning, `docs/specs/model-phase-pinning.md` AC3):** der `dba`-Dispatch in Stufe b ist **immer** der **Design-Modus** (Datenmodell-Entwurf → `docs/data-model.md`) — dieser erhält **in jedem Cost-Mode** (auch `low-cost`/`balanced`) einen festen `model: opus`-Override, unabhängig von der `dba`-Matrix-Zeile (die nur den **Review-Modus** des `dba` beschreibt, siehe `knowledge/model-tiers.md` „Design-Rollen-Pinning"). `requirement` (Stufe c), `architekt` (Stufe b) und `designer` (Stufe b, bei UI-Projekten, siehe unten) folgen weiterhin normal der Matrix (dort bereits als Design-Rollen gepinnt) — `designer` steht durchgängig in **jedem** Cost-Mode auf `opus` (`knowledge/model-tiers.md`), eine `dba`-artige Sonderbehandlung ist für ihn nicht nötig. Das `--cost`-Token gehört NICHT zum Ordnerpfad — vor der Argument-Auswertung herausparsen. Ebenso die **`--sync`**/**`--audit`**-Tokens (Modus-Wahl, siehe *Modus-Wahl* oben): vor der Ordnerpfad-Auswertung herausparsen; `--sync` → **Re-Sync** (§5), `--audit` → **Audit** (§6), sonst Ingest.
- **Headless-Signal auflösen (`--gui`, AC23):** ebenfalls **vor** der Ordnerpfad-Auswertung das Token **`--gui`** herausparsen (gehört NICHT zum Ordnerpfad). Gesetzt → **`HEADLESS_JSON=1`**: das Fragenkatalog-Gate wird **nicht** interaktiv (`AskUserQuestion`) gestellt, sondern als **JSON-Wrapper** ausgegeben (Regeln unter **Headless-Modus** unten). Nicht gesetzt → interaktives Verhalten **unverändert**. `--gui` ist mit `--sync`/`--cost` kombinierbar; es ändert **nur** den Gate-Ausgabekanal, **nicht** die Stufen-Logik/Reihenfolge/Schreibzonen.
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

## 0c-headless. Headless-Modus (`--gui`) — JSON-Endausgabe je Runde (AC23–AC25)

Läuft der Skill mit **`HEADLESS_JSON=1`** (§0, Token `--gui`), steht **kein** interaktiver `AskUserQuestion`-Adressat zur Verfügung — der Aufrufer ist der dev-gui-`ObsidianIngestRunner` (`claude -p '/agent-flow:from-notes --gui <ordner>' --output-format json`, `.result` = finale Assistant-Nachricht). Dann gilt für **jedes** Stufen-Gate (§1.2 Stufe a, §2.3 Stufe b, §3.2 Stufe c, §5.4 `sync`) und für das **Runden-Ende** dieser **harte Ausgabe-Vertrag** (AC24):

- **Anstehendes Gate** (Validator-Token `valid`, ≥1 Frage): **statt** `AskUserQuestion` die Runde mit **genau EINEM** JSON-Objekt als **letzter Ausgabe** beenden — nichts danach ausgeben, dann die Runde beenden (die Antworten kommen im Resume):
  ```json
  { "status": "needs-answers", "catalog": <der validierte KATALOG-JSON-Array, unverändert> }
  ```
  `catalog` ist **exakt** die JSON-Liste der Frage-Objekte, die ohnehin für dieses Gate aufgebaut und durch `scripts/obsidian-fragenkatalog-validate.sh` als `valid` bestätigt wurde (Feldmenge `stage`/`id`/`frage`/`quelle`/optional `optionen`, `board/fragenkatalog.schema.json`). **Kein** einleitender/erklärender Fliesstext, **kein** Text nach dem JSON.
- **Kein offenes Gate mehr** (alle Stufen durchlaufen, Validator `empty` auf allen Gates, Board-Items angelegt): die Runde mit **genau** `{ "status": "done" }` als letzter Ausgabe beenden.
- **Resume nach Antworten:** Reicht der Runner die Antworten zurück (`--resume`, Zuordnung je Frage über `id`), setzt der Skill die unterbrochene Stufe mit den Antworten fort (Katalog einarbeiten → committen → nächste Stufe) und beendet die **Resume-Runde** wieder **exakt** nach diesem Vertrag — nächstes anstehendes Gate → `needs-answers`, sonst `done`. Jede Runde (initial **und** jeder Resume) endet so.
- **Fehlerpfad (AC25):** klarer Abbruch (E1/E2), Aufruffehler oder Katalog-Vertragsverletzung dürfen weiterhin mit **exitCode ≠ 0** / Freitext enden — **kein** künstliches `{status:…}`-JSON über einen echten Fehler legen. Der JSON-Vertrag gilt nur für reguläre Runden-Enden.

**Disziplin (hart, AC24):** Im `--gui`-Modus ist die **finale Assistant-Nachricht** der Runde **ausschliesslich** das JSON-Objekt. Das gilt auch nach den Sub-Agent-Stufen b/c (`designer`/`requirement`): der Skill fasst deren Ergebnis **nicht** in Prosa zusammen, sondern gibt das Gate/`done` als JSON aus — die zu einem Gate gesammelten Fragen sind der **Skill-eigene** Katalog, nicht ein durchgereichtes Sub-Agent-Result (vgl. Präzedenz `[[regression-define]]` AC12, wo eine orchestrierende Session ein Sub-Agent-Ergebnis konversationell zusammenfasste — hier bewusst vermieden). Ohne `--gui` bleibt alles interaktiv (`AskUserQuestion`), unverändert.

## 0c. PM-Import-Klassifikation (`docs/specs/pm-import.md` AC1, additiv)

Vor Stufe a klassifiziert die Pipeline jede Notiz des Korpus (`$CORPUS_FILE`) **frontmatter-first** als pm-skills-Artefakt oder eben nicht:

1. **`artifact:`-Feld im Frontmatter vorhanden** → dieser Wert gilt. Zulässige Typen: `prd | problem-statement | hypothesis | user-stories | acceptance-criteria | edge-cases | adr | launch-checklist`.
   - **Wert nicht in dieser Liste** → **kein** stiller Ideen-Pfad-Fallback: Eintrag im Stufe-a-Fragenkatalog (`stage:"a"`, `id`-Muster `a-<n>`, `frage`: „Notiz <Herkunfts-Marker> trägt unbekannten Artefakt-Typ '<wert>' — welcher der zulässigen Typen ist gemeint, oder ist es doch eine freie Ideennotiz?", `quelle` = Herkunfts-Marker) — Abgrenzung (pm-import Edge-Cases): fehlendes Feld ⇒ Heuristik (2.), unbekannter Wert ⇒ Rückfrage.
2. **Feld fehlt** → Struktur-Heuristik anwenden (Signale synchron mit `scripts/pm-intake-gate.py::looks_like_pm`, siehe `docs/specs/pm-import.md` → Verträge → Heuristik-Signale): `FR-n` + Sektion „Functional Requirements" → `prd`; `Given`/`When`/`Then`-Zeilen → `acceptance-criteria`; Sektionen „Decision" + „Consequences" → `adr`; `US-n` + Sektion „User Stories" → `user-stories`.
   - **Kein Signal trifft** → **unklassifiziert**, läuft **unverändert** den bestehenden Ideen-Pfad weiter (kein Verhaltensunterschied gegenüber dem Stand vor dieser Erweiterung — deckt auch künftige pm-skills-Formatänderungen, deren Struktur die Heuristik noch nicht kennt, AC1 Edge-Cases).
   - **Heuristik erkennt PM-Struktur, aber unvollständig/mehrdeutig** (E1 — z.B. eine für den vermuteten Typ charakteristische Sektion fehlt oder widerspricht sich) → ebenfalls **kein** stiller Ideen-Pfad-Fallback: Fragenkatalog-Eintrag „als `<typ>` erkannt, Sektion `<x>` fehlt/widersprüchlich" (`quelle` = Herkunfts-Marker).
3. **Container (`artifact: prd`):** zusätzlich zum Notiz-Typ die **enthaltenen Sektionen** markieren (Problem Statement, Goals, Non-Goals, Scope, User Stories, Functional Requirements, Edge Cases, Risks, Success Metrics, Open Questions, Milestones/Launch-Checklist, Revision History) — jede folgt in Stufe b **derselben Mapping-Tabellen-Zeile** wie das gleichnamige Einzelartefakt (Sektionsebene, AC2).

Das Klassifikations-Ergebnis (Typ je Notiz, Sektionsliste bei `prd`) ist **Lauf-lokal** — kein neues Frontmatter-Feld, keine Zusatzdatei dieser Stufe (der `artifact:`-Stempel selbst stammt von pm-skills, nicht von dieser Pipeline) — und begleitet den Korpus durch Stufe a und b. Fragenkatalog-Einträge dieses Schritts fahren im **selben** Stufe-a-Katalog wie 1.2 (kein zweiter Katalog, AC7).

## 0d. PM-Import — Idempotenz, ID-Kette, Drift (`docs/specs/pm-import.md` AC6/AC7/AC10, kein Sonderfall)

Für klassifizierte PM-Notizen (0c) gelten Idempotenz, ID-Kette und Drift-Erkennung **exakt** wie für jede andere Ideennotiz — diese drei ACs fügen **keinen** neuen Pfad, kein neues Frontmatter-Feld und keine neue Vault-Schreiboperation hinzu, sondern machen die Anwendung der bestehenden Mechanik (§1.3/§1.4 Ingest, §5 Re-Sync, §6 Audit) auf PM-Quellen explizit:

- **Idempotenz beim Re-Ingest (AC6):** Eine bereits übernommene PM-Notiz ist über ihre Frontmatter-`idea_id`/`sync_hash` als solche erkennbar (§1.3/§1.4, `obsidian-ingest` AC15/AC17). Unverändertem Inhalt (`sync_hash` deckungsgleich) folgt keine Zusatzaktion. Hat sich der Inhalt seit dem letzten Stempel geändert, wenden Stufe b/c **dieselbe** Mapping-Zeile (§2.1) wie beim Erst-Ingest an und **aktualisieren** das bereits erzeugte Ziel-Artefakt an seinem bestehenden Anker **statt** ein Duplikat anzulegen: der `AC<n>`-Bullet mit passendem `(← FR-n)`/`(← US-n)`-Provenienz-Anhang, der `BR-NNN`-Block, die ADR-Datei (`docs/architecture/<thema>.md`) bzw. der referenzierte `C-NNN`-Konzeptabschnitt werden über ihren Provenienz-Anker wiedergefunden und in-place fortgeschrieben. **Zusätzlicher Vergleichsanker:** trägt die Quellnotiz eigene Versionsdaten (Frontmatter `version:`, Abschnitt „Revision History"), wird der Wert **neben** `sync_hash` im Commit-Message-Body **derjenigen Stufe protokolliert, die das jeweilige Ziel-Artefakt tatsächlich schreibt** (`PM-Version: <notiz> = <wert>`) — reine Protokollierung als Nachvollzugshilfe für den Menschen, **kein** neues Frontmatter-Feld, **keine** zusätzliche Vault-Schreiboperation über §1.4 hinaus. Da **acht** der elf Mapping-Zeilen (§2.1) direkt in Stufe-b-Ziele fliessen (Spec-`AC<n>`, `BR-NNN`, ADR-Datei, …) und `docs/concept.md` dabei **nicht** geändert wird, ist der **primäre** Ort dafür der **Stufe-b-Commit** (§2.4). Die **neunte** Zeile — `launch-checklist`/`prd`: Milestones — hat dagegen **kein** Stufe-b-Schreibziel (§2.1, AC8): sie wird Lauf-lokal gesammelt und erst in Stufe c als Zerlege-Hinweis verwendet (§3.1); für sie ist der primäre Ort daher der **Stufe-c-Commit** (§3.3), und zwar nur dort, wo aus ihren Zerlege-Hinweisen tatsächlich ein Board-Item entstanden ist. Nur die **zwei** in Stufe a verbleibenden Zeilen (Risiken/Success Metrics, Open Questions, §1.1) protokollieren zusätzlich im Stufe-a-Commit (§1.5) — jeweils nur dort, wo diese Stufe für die Notiz tatsächlich ein Ziel-Artefakt fortgeschrieben hat (kein Commit ohne geschriebenes Ziel, kein „toter" Vermerk).
- **ID-Kette unverändert (AC7):** PM-Artefakte erhalten `IDEA-NNN` (§1.3) und den Frontmatter-Stempel (§1.4) exakt wie jede andere übernommene Notiz — kein eigener PM-Zweig der ID-Vergabe, keine eigenen Feldnamen. Die Kette `IDEA → C → Spec → BR → Story → @trace` bleibt für PM-Quellen durchgängig verankert (Konzept-Herkunft `(← C-NNN)`, `BR-NNN` aus §2.1 AC3, AC-Provenienz aus §2.1 AC4); `--audit` (§6, `obsidian-ingest` AC19–AC22) prüft sie **ohne** Sonderfall — im Frontmatter-Scan (§6.1) sind PM-Notizen gewöhnliche Vault-Notizen mit `idea_id`/`c_refs`, in der Waisen-/Widerspruchs-Klassifikation (§6.2) gelten dieselben Regeln wie für jede andere Notiz.
- **Drift-Erkennung (AC10):** Ändert sich eine bereits übernommene PM-Quellnotiz nachträglich, greift **ausschließlich** der bestehende `sync_hash`-Mechanismus — gemeldet über `--audit` (§6) bzw. `--sync` (§5, Drei-Wege-Anker `obsidian-sync` AC7). **Keine neue Mechanik**, kein separater PM-Drift-Pfad.

## 1. Stufe a — Notiz-Korpus → `docs/concept.md` (AC11a, kritischste Stufe)

**Ziel:** den Notiz-Korpus zum Konzept konsolidieren (Problem · Nutzer · Ziele · Nicht-Ziele · Scope). Diese Stufe ist der **kritische Punkt** (Subsystem §1/§3): eine ungenaue Erst-Übersetzung vererbt Fehler an Spec und Stories.

1. **Übersetzen (niedrigste Nachfrage-Schwelle, AC10):** Aus `$CORPUS_FILE` das Konzept nach `docs/concept.md` schreiben (Skelett `templates/_docs/concept.md`; existiert bereits ein Root-`CONCEPT.md`-Layout wie in manchen Projekten, dort die betroffenen Sektionen ergänzen statt einer neuen Datei — dieselbe Layout-Konvention wie `reconcile`). **Jede** relevante Mehrdeutigkeit/jeder Widerspruch im Ideen-Text wird zur **Frage** (Fragenkatalog-Eintrag), **nicht** zur stillen Annahme — die Schwelle ist hier bewusst niedrig (AC10). Jeder Katalog-Eintrag trägt im `quelle`-Feld den Herkunfts-Marker der Quellnotiz. **Klassifizierte PM-Notizen (0c) — jede Mapping-Zeile hat ein definiertes Ziel, kein Rest-Fallback mehr (`docs/specs/pm-import.md` AC3/AC4/AC5/AC8/AC9):** **Neun** Mapping-Zeilen fliessen **nicht** in diesen Übersetzungsschritt, sondern direkt an ihr feldgenaues Ziel in Stufe b bzw. c: `problem-statement`/`prd`: Problem Statement (+ Goals) → Zweck · `prd`: Non-Goals → Nicht-Ziele · `prd`: Scope → Verträge/Abhängigkeiten · `user-stories`/`prd`: User Stories → Main Success Scenario/Alternative Flows · `edge-cases`/`prd`: Edge Cases → Edge-Cases & Fehlerverhalten (alle fünf: Stufe b §2.1) sowie `hypothesis` → `BR-NNN`-Kandidat (Stufe b §2.1, AC3) · `acceptance-criteria`/`prd`: Functional Requirements (`FR-n`) → Spec-Acceptance-Kriterien (Stufe b §2.1, AC4) · `adr` → `docs/architecture/<thema>.md` (Stufe b §2.1, AC9) · `launch-checklist`/`prd`: Milestones → Zerlege-Hinweise für Stufe c (§3.1, AC8). **Zwei** Zeilen bleiben in **diesem** Schritt, aber mit eigener, definierter Behandlung statt der generischen Mehrdeutigkeits-Schwelle:
   - `prd`: Risiken, Success Metrics → eigener Absatz/eigene Aufzählung in `docs/concept.md` mit Herkunftsvermerk; **zusätzlich** ein Fragenkatalog-Eintrag, wenn der Punkt entscheidungsrelevant ist (AC5) — kein Spec-Feld.
   - `prd`: Open Questions → **immer** 1:1 als Fragenkatalog-Eintrag (`stage:"a"`, `quelle` = Herkunfts-Marker + Sektionsname „Open Questions"), unabhängig davon, ob die einzelne Frage für sich genommen mehrdeutig wäre (AC5) — landet **nicht** in `docs/concept.md`.

   Nur **unklassifizierte** Notizen (0c) durchlaufen wie bisher unverändert die generische Übersetzung mit der niedrigen Mehrdeutigkeits-Schwelle.
2. **Fragenkatalog-Gate (AC7/AC8/AC9):** Alle offenen Punkte dieser Stufe **gesammelt** als **genau EINE** JSON-Liste von Frage-Objekten aufbauen — je Objekt `stage:"a"`, `id` (katalog-eindeutig, Muster `a-<n>`), `frage`, `quelle` (Notiz-Fundstelle), optional `optionen[]` (Format-Vertrag: `board/fragenkatalog.schema.json`). Den Katalog durch den wiederverwendeten Gate-Validator prüfen und das Vorlege-Verhalten am stdout-Token festmachen:
   ```bash
   printf '%s' "$KATALOG_A_JSON" | bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-fragenkatalog-validate.sh"
   ```
   - **`empty`** → keine offenen Fragen → **Auto-Durchlauf** (AC8): kein Katalog vorlegen, direkt zu 1.3 (ID-Kette).
   - **`valid`** → nicht-leerer Katalog → dem User **am Stück** vorlegen (AC7): **`HEADLESS_JSON=1`** (`--gui`, §0c-headless) → die Runde mit `{ "status": "needs-answers", "catalog": <dieser validierte Katalog> }` als **letzter Ausgabe** beenden (kein `AskUserQuestion`, kein Fliesstext danach); der Runner reicht die Antworten im Resume zurück (AC24). **Sonst** (interaktiv) im Terminal-Pfad via `AskUserQuestion` (ein Prompt, alle Fragen zusammen). **Erst nach** vollständiger Beantwortung fließen die Antworten in `docs/concept.md` ein.
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
   Der Profilfeld-Diff (`obsidian_source`, §0a) fährt hier mit. `.claude/profile.md` nur `git add`en, wenn §0a das Feld tatsächlich gesetzt/geändert hat. Lehnt Branch-Protection den Direkt-Push ab → docs-only-PR öffnen + selbst mergen (analog `requirement`-Skill). Der Notiz-Ordner wird **nie** ge-`add`et (AC6/AC14). **Trägt eine übernommene PM-Notiz eigene Versionsdaten** (Frontmatter `version:`, Abschnitt „Revision History", `docs/specs/pm-import.md` AC6/§0d) **und wurde in diesem Schritt für sie tatsächlich ein Abschnitt in `docs/concept.md` geschrieben** (Risiken/Success Metrics bzw. Open Questions, §1.1 — die einzigen zwei Mapping-Zeilen, die hier statt in Stufe b landen): den Wert als zusätzliche Zeile im Commit-Message-Body mitführen (`PM-Version: <notiz> = <wert>`) — reine Protokollierung, kein neues Frontmatter-Feld. Fliessen alle Mapping-Zeilen dieser Notiz direkt in Stufe-b- oder Stufe-c-Ziele (Regelfall, neun von elf Zeilen, §2.1), bleibt `docs/concept.md` für sie unverändert und der Vermerk unterbleibt hier — er erscheint stattdessen im jeweiligen Ziel-Stufen-Commit (Stufe b, §2.4, für acht der neun Zeilen; Stufe c, §3.3, für die `launch-checklist`-Zeile).

Stufe b startet **erst nach** committetem Stufe-a-Ergebnis (harte Reihenfolge, AC12).

## 2. Stufe b — `docs/concept.md` → `docs/specs/<feature>.md` (AC11b/AC13)

**Ziel:** je Capability des Konzepts **eine** durable Spec ableiten, den bestehenden **Spec-Vertrag wiederverwenden** (AC13) — Vorlage, `spec_format`-Stempel, nummerierte AC, Traceability.

1. **Spec(s) schreiben:** je Capability eine `docs/specs/<feature-slug>.md` aus `templates/_docs/specs/_template.md` — Zweck, Verhalten, **nummerierte Acceptance-Kriterien (AC1, AC2, …)**, Verträge, Edge-Cases, NFRs, Nicht-Ziele. **`spec_format`-Stempel:** den Wert 1:1 aus der **aktuellen** `_template.md` übernehmen (nicht hartkodieren), wie es der Spec-Vertrag (`docs/specs/spec-format-field.md` AC3) und `requirement` fordern. **Konzept-Herkunft:** jede Spec referenziert ihre `C-NNN`-Herkunft `(← C-NNN)` (AC16).
   - **Mapping-Dispatch für klassifizierte PM-Notizen (0c, `docs/specs/pm-import.md` AC2):** für jede in 0c klassifizierte Notiz bzw. `prd`-Sektion die **Mapping-Tabelle** (`docs/specs/pm-import.md` → Verträge) nachschlagen und den Inhalt **deterministisch** an das dort genannte Ziel schreiben — gleicher Input erzeugt immer dieselbe Zuordnung, **keine** freie Neu-Interpretation von Inhalten mit definiertem Ziel. **Container (`prd`):** jede in 0c markierte Sektion wird **einzeln** nach ihrer eigenen Zeile behandelt (Sektionsebene), nicht die gesamte Notiz nach einer Zeile. Angewandte Zeilen (vollständig, kein Rest-Fallback):
     - `problem-statement` / `prd`: Problem Statement (+ ergänzend `prd`: Ziele/Goals) → Spec «Zweck» (auf 1–2 Sätze verdichtet, zusammengeführt).
     - `prd`: Non-Goals → Spec «Nicht-Ziele» (1:1).
     - `prd`: Scope → Spec «Verträge» + «Abhängigkeiten» (Scope-Elemente aufteilen).
     - `user-stories` / `prd`: User Stories (`US-n`) → Spec «Main Success Scenario» + «Alternative Flows» (Story → Flow-Schritt; Flows optional): jede User Story wird zu **einem** Schritt im Main Success Scenario bzw. einem Alternative Flow. **Provenienz-Anhang** (Terminologie-Gleichstand mit der `FR-n`-Konvention, `docs/specs/pm-import.md` AC4): die Quell-`US-n` wird als Anhang direkt an den Flow-Schritt geschrieben (`<n>. <Schritt-Text> (← US-n)`), damit die Herkunft im Mapping-Protokoll ebenso nachvollziehbar bleibt wie bei `(← FR-n)`.
     - `edge-cases` / `prd`: Edge Cases → Spec «Edge-Cases & Fehlerverhalten» (1:1).
     - `hypothesis` → `BR-NNN`-Kandidat (`docs/specs/pm-import.md` AC3): **Nummer** wie bei `IDEA-NNN`/`C-NNN` (§1.3) — höchste bestehende `BR-NNN` über `docs/architecture.md` **und** `docs/data-model.md` per Scan ermitteln (`grep -rhoE '\bBR-[0-9]+\b' docs/architecture.md docs/data-model.md`), +1, nie wiederverwendet. **Ziel-Datei:** verhaltensbezogene Hypothesen → `docs/architecture.md` (Sektion „Geschäftsregeln (BR-NNN)", neuer `### BR-NNN: <Kurztitel>`-Block); datenvalidierende Hypothesen (Format/Wertebereich/Pflichtfeld) → `docs/data-model.md` (Sektion „Validierungs-Geschäftsregeln (BR-NNN)", neue Tabellenzeile) — dieselbe fachliche Abgrenzung wie in beiden Vorlagen dokumentiert. **Markierung „Kandidat"** (Hypothese, noch nicht bestätigt): in `architecture.md` als Zusatz in der Überschrift (`### BR-NNN: <Kurztitel> (Kandidat)`), in `data-model.md` als Zusatz im `Regel`-Zellenwert (`<Regel-Text> (Kandidat)`); das **Messkriterium** der Hypothese (woran ihre Bestätigung/Widerlegung gemessen wird) als Folgesatz (`architecture.md`) bzw. mit in der `Regel`-Zelle mitgeführt (`data-model.md`). Die Ziel-Spec referenziert die Regel ausschliesslich via `(→ BR-NNN)` — kein Duplizieren des Regeltexts in der Spec.
     - `acceptance-criteria` (GWT) / `prd`: Functional Requirements (`FR-n`) → Spec «Acceptance-Kriterien» (`docs/specs/pm-import.md` AC4): jede GWT-Einheit bzw. jedes `FR-n` wird zu **einem** nummerierten `AC<n>` der Ziel-Spec, fortlaufend an bestehende ACs angehängt (**nie** umnummerieren — Re-Ingest hängt neue Punkte nur hinten an, AC-IDs sind stabil). **Mapping-Protokoll:** die Quell-ID (`FR-n` bzw. die GWT-Quellzeile) wird als Provenienz-Anhang direkt an den AC-Bullet geschrieben (`- **AC<n>** — <Titel>: <GWT/FR-Text als testbare Aussage> (← FR-n)`), analog der `(← C-NNN)`-Konvention der Spec-Herkunft. Die `@trace <feature-slug>#AC<n>[,BR-NNN]`-Konvention bleibt für den `tester` unverändert.
     - `adr` → `docs/architecture/<thema>.md` (`docs/specs/pm-import.md` AC9): Themen-Slug aus dem ADR-Titel (H1 bzw. Frontmatter-`title`) ableiten, kebab-case, analog dem Feature-Slug-Verfahren (siehe „Feature-Slug bei PRD-Herkunft" unten). Existiert bereits eine `docs/architecture/<thema>.md` mit überschneidendem Scope → dort ein neuer ADR-Block anhängen; sonst neue Datei anlegen. Nygard-Format 1:1 aus der Notiz übernehmen (Status/Kontext/Entscheidung/Konsequenzen) — **kein** Zwang, den ADR-Inhalt in eine Feature-Spec zu kopieren, stattdessen ein Verweis `[[<thema>]]` unter «Abhängigkeiten» der betroffenen Ziel-Spec.
     - `launch-checklist` / `prd`: Milestones → Zerlege-Hinweise für Stufe c (`docs/specs/pm-import.md` AC8): **kein** Stufe-b-Schreibziel — die Punkte werden Lauf-lokal gesammelt (wie das Klassifikations-Ergebnis aus 0c) und in Stufe c (§3.1) als Zerlege-Hinweis an den `requirement`-Dispatch weitergereicht.
     - Frontmatter `version` / Revision History → Idempotenz-/Divergenz-Anker (`docs/specs/pm-import.md` AC6, Details §0d): zusätzlicher Vergleichsanker neben `sync_hash`. **Primär** protokolliert **hier** in der **Stufe-b-Commit-Message** (§2.4) — dem Ort, an dem acht der direkt gemappten Zeilen ihr Ziel-Artefakt (Spec-`AC<n>`, `BR-NNN`, ADR-Datei, …) tatsächlich schreiben; die neunte Zeile (`launch-checklist`, s.o.) protokolliert stattdessen im **Stufe-c-Commit** (§3.3), da sie erst dort ihr Ziel (Board-Item) schreibt; keine eigene zusätzliche Vault- oder Doc-Schreiboperation dieser Erweiterung.

     `prd`: Risiken/Success Metrics und `prd`: Open Questions sind **Stufe-a-Ziele** (nicht hier) — siehe §1.1.
   - **Feature-Slug bei PRD-Herkunft:** `id` = kebab-case-Slug aus dem PRD-Titel (H1 bzw. Frontmatter-`title`), stabil (Verträge, „Frontmatter der erzeugten Spec"). Kollidiert der Slug mit einer bestehenden Spec-`id` → Fragenkatalog-Eintrag („Zusammenführen vs. neuer Slug"), **nie** stilles Überschreiben (pm-import Edge-Cases).
2. **Tiefes Detail via bestehende Agenten (AC11b/AC13 — kein Neubau):** Wo tiefes Architektur-Detail nötig ist, den **`architekt`**-Agenten (Task) dispatchen → `docs/architecture.md` bzw. `docs/architecture/<subsystem>.md`. Wo ein Datenmodell nötig ist, den **`dba`**-Agenten (Task, **Design-Modus**) → `docs/data-model.md` — dieser Dispatch bekommt **immer** `model: opus` (Design-Rollen-Pinning, siehe §0), unabhängig vom aktiven Cost-Mode. **Bei UI-Projekten** (`language` ∈ flutter|angular|html **oder** Domäne `ui`/`accessibility` — dieselbe Erkennung wie `new-project`, `docs/specs/design-owner-approval.md` AC3) zusätzlich den **`designer`**-Agenten (Task, **Vorschlags-Modus**, `agents/designer.md`-Vertrag — kein Neubau) dispatchen → `docs/design.md` als **Entwurf** (`owner_approved: null`) anlegen/fortschreiben; läuft ebenfalls **immer** auf `model: opus` (Design-Rollen-Pinning, siehe §0). **Katalog-Übergabe statt eigener Owner-Vorlage (genau EIN Katalog pro Stufe, AC3):** der Designer-Dispatch bekommt hier den Auftrag, **nicht** seine eigene Owner-Vorlage zu präsentieren (Vertrags-Schritt 4 in `agents/designer.md`, eigenständiges `AskUserQuestion`/`stage:"design"`), sondern seine offenen Gestaltungsfragen **im Stufe-b-Format** zurückzugeben (`stage:"b"`, `id`-Muster `b-<n>`, an die bereits gesammelten Stufe-b-Fragen anschliessend nummeriert) — Zusammenfassung + konkrete Optionen bleiben inhaltlich wie im Designer-Vertrag (Alltagssprache, keine Token-/Fachjargon). Alle drei Agenten (`architekt`/`dba`/`designer`) schreiben nur in den Working-Tree (kein Commit) — das Committen macht dieser Skill in 2.4.
3. **Fragenkatalog-Gate (AC7/AC8/AC9):** identische Mechanik wie 1.2, aber `stage:"b"`, `id`-Muster `b-<n>`, `quelle` = Konzept-/Doku-Fundstelle. **Design-Fragen** (falls Schritt 2 den `designer` dispatcht hat) fahren als reguläre `b-<n>`-Einträge im **selben** Katalog mit — es entsteht **genau EIN** Stufe-b-Katalog, nie ein zweiter, separater Design-Katalog (`design-owner-approval` AC3). `empty` → Auto-Durchlauf; `valid` → dem User am Stück vorlegen — **`HEADLESS_JSON=1`** (`--gui`, §0c-headless): Runde mit `{ "status": "needs-answers", "catalog": <dieser validierte Stufe-b-Katalog> }` als letzter Ausgabe beenden (kein `AskUserQuestion`, kein Fliesstext, Antworten im Resume, AC24); **sonst** interaktiv via `AskUserQuestion`. Auch nach dem `designer`-Dispatch gilt: **kein** Prosa-Zusammenfassen des Sub-Agent-Ergebnisses im `--gui`-Modus — das Gate wird als JSON ausgegeben. Erst nach Beantwortung fließen die Antworten in die Spec(s)/Architektur/`docs/design.md` ein — designbezogene Antworten reicht dieser Skill an den `designer`-Kontext zurück, damit er `docs/design.md` entsprechend fortschreibt. `docs/design.md` bleibt dabei **Entwurf** (`owner_approved: null`) — die eigentliche Owner-**Freigabe**/Stempelung (AC2) ist ein separater Schritt und erfolgt spätestens am `/flow`-Erst-Design-Gate vor der ersten UI-Story (AC5/AC6, ausserhalb dieses Skills).
4. **Commit Stufe b (AC12):** Erst nach beantwortetem/leerem Katalog:
   ```bash
   git add docs/ && git commit -m "notes(b): Konzept -> docs/specs/<…> (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Alle in dieser Stufe berührten `docs/`-Dateien (Spec(s) + ggf. `architecture*.md`/`data-model.md`/**`design.md` bei UI-Projekten**) fahren in **einem** Stufe-b-Commit (`git add docs/` erfasst `docs/design.md` automatisch mit). Branch-Protection → docs-only-PR + Self-Merge. **Trägt eine übernommene PM-Notiz eigene Versionsdaten** (Frontmatter `version:`, Abschnitt „Revision History", `docs/specs/pm-import.md` AC6/§0d) **und wurde in dieser Stufe eines ihrer Mapping-Ziele tatsächlich geschrieben/fortgeschrieben** (Spec-`AC<n>`, `BR-NNN`-Block, ADR-Datei, …) — das ist der **Regelfall** (acht von elf Mapping-Zeilen, §2.1): den Wert als zusätzliche Zeile im Commit-Message-Body mitführen (`PM-Version: <notiz> = <wert>`) — reine Protokollierung, kein neues Frontmatter-Feld, keine zusätzliche Vault-Schreiboperation. (Die zwei übrigen Zeilen — Risiken/Success Metrics, Open Questions — protokollieren stattdessen im Stufe-a-Commit, §1.5; die verbleibende neunte Zeile — launch-checklist — protokolliert im Stufe-c-Commit, §3.3.)

Stufe c startet **erst nach** committetem Stufe-b-Ergebnis (harte Reihenfolge, AC12).

## 3. Stufe c — Spec(s) → Board-Items/Stories über den `requirement`-Agenten (AC11c/AC13)

**Ziel:** die in Stufe b entstandenen Spec(s) in Board-Items/Stories zerlegen — **über den bestehenden `requirement`-Agenten** (AC11: „kein zweiter Zerlege-Pfad").

1. **`requirement`-Agent dispatchen (Task, `agents/requirement.md`):** als Eingabe die in Stufe b geschriebene(n) Spec(s) übergeben — nicht eine neue vage Anforderung, sondern der Verweis auf die bereits durable Spec(s) mit dem Auftrag, sie in Board-Items zu zerlegen. Der `requirement`-Agent leistet dabei **ohnehin** (AC13):
   - Zerlegung in TODOs (je Item ≈ ein coder→reviewer→tester-Durchlauf),
   - je Item ein Board-Item (**To Do**), das auf **Spec + AC-Nummern** zeigt (**kein** eingebetteter AC-Text),
   - die **A-priori-Schätzung** (`size_est`/`dispo_est`/`confidence`/`estimate_note`) bei der Anlage.

   Da die Spec(s) bereits geschrieben sind, sollte der `requirement`-Agent hier i.d.R. **nicht** erneut Spec-schreiben — sein Fokus ist die Zerlegung. Legt er dabei doch Spec-Feinschliff nach (Working-Tree), fährt der in den Stufe-c-Commit (3.3).
   - **Launch-Checklist-Zerlege-Hinweise (`docs/specs/pm-import.md` AC8):** wurden in Stufe b (0c/§2.1) `launch-checklist`- bzw. PRD-`Milestones`-Punkte gesammelt, werden sie diesem Dispatch als **zusätzlicher Kontext** für die Zerlegung mitgegeben (kein Board-Feld, kein zweiter Item-Pfad) — die daraus entstehenden Board-Items zeigen wie immer **ausschliesslich** auf Spec + AC-Nummern, **kein** eingebetteter Checklisten-Text.
2. **Fragenkatalog-Gate (AC7/AC8/AC9):** Bleiben bei der Zerlegung Unklarheiten offen (z.B. Schnitt-Granularität, Priorität, Abhängigkeiten), diese **gesammelt** als **einen** Katalog `stage:"c"` (`id`-Muster `c-<n>`, `quelle` = Spec-/Doku-Fundstelle) — Validator + Vorlege-Verhalten wie oben (im `--gui`-Modus als `{ "status": "needs-answers", "catalog": … }`-Runden-Ende, §0c-headless/AC24; auch hier **kein** Prosa-Zusammenfassen des `requirement`-Sub-Agent-Ergebnisses). Der `requirement`-Agent stellt seine eigenen gezielten Rückfragen normalerweise selbst; ein separater Stufe-c-Katalog wird nur aufgebaut, wenn nach seinem Lauf noch pipeline-seitige Unklarheiten offen sind (kein leerer Katalog, AC8).
3. **Commit Stufe c (AC12):** Der `requirement`-Agent legt die Board-Items an (Status **To Do**, `/flow`-Hoheit endet dort — kein Status-Vorschub, AC14). Etwaige vom Agenten in den Working-Tree geschriebene `docs/`-Deltas dieser Stufe committen:
   ```bash
   git add docs/ && git commit -m "notes(c): Spec(s) -> Board-Items (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Gibt es keinen `docs/`-Delta in Stufe c (Items liegen im File-Board bzw. via `gh` am GitHub-Board), entfällt der Doc-Commit — die Board-Items selbst sind der durable Zustand dieser Stufe. **Trägt eine übernommene PM-Notiz eigene Versionsdaten** (Frontmatter `version:`, Abschnitt „Revision History", `docs/specs/pm-import.md` AC6/§0d) **und ist in dieser Stufe für sie aus ihren launch-checklist-Zerlege-Hinweisen (§3.1, AC8) tatsächlich ein Board-Item entstanden** — die `launch-checklist`/`prd`: Milestones-Zeile hat als einzige der elf Mapping-Zeilen kein Stufe-b-Schreibziel (§2.1, AC8) und wird erst hier verwertet: den Wert als zusätzliche Zeile in der Commit-Message dieses Schritts mitführen (`PM-Version: <notiz> = <wert>`), bzw. — entfällt der Doc-Commit mangels `docs/`-Delta — als gleichlautende Zeile im Task-Abschlusskommentar des `requirement`-Dispatches vermerken. Reine Protokollierung, kein neues Frontmatter-Feld, keine zusätzliche Vault-Schreiboperation. Ist aus den Zerlege-Hinweisen dieser Notiz kein Board-Item entstanden, unterbleibt der Vermerk hier (kein Commit ohne geschriebenes Ziel, kein „toter" Vermerk).

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

**Im `--gui`-Modus (`HEADLESS_JSON=1`, AC24)** ist die obige menschenlesbare Zusammenfassung **nicht** die finale Ausgabe: Die Runde endet **ausschliesslich** mit dem JSON-Wrapper (`{ "status": "needs-answers", "catalog": [ … ] }` bei anstehendem Gate, sonst — nach Stufe c committet und Board-Items angelegt — `{ "status": "done" }`) als **letzter Ausgabe** (§0c-headless). Kein Fliesstext danach.

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
   - **`valid`** → dem User **am Stück** vorlegen: **`HEADLESS_JSON=1`** (`--gui`, §0c-headless) → die Runde mit `{ "status": "needs-answers", "catalog": <dieser validierte sync-Katalog> }` als **letzter Ausgabe** beenden (kein `AskUserQuestion`, kein Fliesstext danach); Antworten kommen im Resume zurück (AC24). **Sonst** (interaktiv) Terminal: `AskUserQuestion`, ein Prompt für alle Divergenzen. **Nie** Einzel-Prompt je Fund verstreut (AC4/Edge).
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
- **Headless-Ausgabevertrag (`--gui`, AC23–AC25):** Mit `--gui` endet **jede Runde** (initial + jeder Resume) mit **genau EINEM** JSON-Objekt als **letzter Ausgabe** — `{ "status": "needs-answers", "catalog": [ … ] }` (Gate erreicht, Stufe a/b/c/sync) bzw. `{ "status": "done" }` (Durchlauf fertig). **KEIN** Fliesstext nach dem JSON, **kein** `AskUserQuestion`, **kein** Prosa-Zusammenfassen von Sub-Agent-Ergebnissen (b/c). Echte Fehler enden weiterhin mit exitCode ≠ 0 / Freitext — **kein** künstliches Status-JSON. Ohne `--gui`: interaktiv, unverändert. `--gui` wird — wie `--cost`/`--sync`/`--audit` — vor der Ordnerpfad-Auswertung herausgeparst und gehört **nicht** zum Ordnerpfad.
- **Re-Sync (`--sync`) — kein Blind-Overwrite, invertierte Reconcile-Autorität (obsidian-sync AC1/AC3/AC6):** der Re-Sync-Modus (§5) überschreibt Konzept/Spec **nie** automatisch; jede Divergenz ist ein per-Fund-User-Entscheid (`uebernehmen`/`behalten`/`manuell`), und **nur** `uebernehmen` schreibt — ausschließlich nach `docs/concept.md`/`docs/specs/*`, nie in den Notiz-Ordner. Er ist ein **eigener Modus** desselben Skills, teilt Reader + Katalog-Gate mit dem Ingest und lässt den **Reconcile-Vertrag unangetastet** (kein Reconcile-„Stufe 0"). **Kein** `/flow`-Start, **keine** automatische Story-Anlage. Bei Deckungsgleichheit: **kein** Katalog, **keine** Änderung, „deckungsgleich"-Meldung.
- **Kein PM-Sonderpfad für Idempotenz/ID-Kette/Drift (`docs/specs/pm-import.md` AC6/AC7/AC10, §0d):** PM-Notizen laufen für Re-Ingest-Idempotenz, `IDEA-NNN`/Frontmatter-Stempel, `--audit`-Abdeckung und Drift-Erkennung durch **dieselbe** Ideen-Pipeline-Mechanik wie jede andere Notiz — kein eigenes Frontmatter-Feld, kein eigener Audit-Zweig, kein eigener Drift-Mechanismus.
