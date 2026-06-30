---
name: reconcile
description: Startet /agent-flow:reconcile — bringt die docs/ eines Projekts wieder mit der Realität in Deckung (rückwärtige Aufholung, Gegenstück zur vorwärtigen Drift-Disziplin). Stufe 1 (Form, läuft IMMER) hebt jede Spec mit veraltetem/fehlendem spec_format-Stempel automatisch auf die aktuelle Vorlage. Stufe 2 (Inhalt, nur bei leerem Kanban) gleicht die Doku-Inhalte gegen den Code ab — noch NICHT implementiert (folgt in S-012), läuft heute nur als Vorbedingungs-Check + Hinweis. Beide Stufen liefern genau EINEN Diff/PR zur Freigabe, protokolliert in docs/spec-audit.md. Kein eigener reconcile-Agent — Orchestrierung lebt komplett in diesem Skill. Aufruf: /agent-flow:reconcile.
---

# /agent-flow:reconcile

Bringt die `docs/` des **aktuellen** Projekt-Repos (cwd) wieder mit der Realität in Deckung — on-demand, in zwei Stufen. **Dieser Skill ist der einzige Schreiber** der Reconcile-Änderungen; es gibt **keinen** separaten `reconcile`-Agent (Vertrag `docs/architecture/reconcile-subsystem.md` §7, Spec `docs/specs/reconcile.md` AC1).

Bindende Quellen: `docs/specs/reconcile.md` (AC1–AC11) + `docs/architecture/reconcile-subsystem.md` (FINAL). **Dieser Skill implementiert Stufe 1 vollständig (AC1–AC5). Stufe 2 (AC6–AC9, Inhalts-Abgleich) ist NICHT Teil dieses Stands** — sie wird in einem Folge-Item (S-012) gebaut. Bis dahin läuft hier **nur** der Kanban-Vorbedingungs-Check (§2) mit klarem Hinweis, kein Inhalts-Abgleich.

## 0. Setup
- `.claude/profile.md` lesen → `merge_policy` (`pr`|`direct`), `default_branch`.
- Bei `merge_policy: pr`: Auth sicherstellen — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-gh-auth.sh"`.
- `git status` — Working-Tree sollte sauber sein, bevor Stufe 1 schreibt (sonst vermischen sich fremde Änderungen mit dem Reconcile-Diff). Ist der Tree nicht sauber: Hinweis ausgeben, User entscheiden lassen, ob fortgefahren wird.

## 1. Stufe 1 (Form) — läuft IMMER (AC2)
Rein doku-intern (kein Code-Bezug) — läuft unabhängig vom Board-Zustand, auch bei vollem Kanban.

### 1a. Erkennung (AC3)
```
bash scripts/reconcile-stage1-detect.sh
```
Liefert pro Zeile TAB-getrennt: `<pfad>  <missing|outdated>  <aktueller-wert>  <ziel-wert>` für jede Spec unter `docs/specs/`, deren `spec_format` vom aktuellen Vorlagenwert (`templates/_docs/specs/_template.md`) abweicht oder ganz fehlt. Eine leere Ausgabe heißt: **keine Form-Drift** → Stufe 1 erzeugt keinen Diff, keinen Logbuch-Block (AC2/E2-Prinzip) — weiter zu §2.

### 1b. Konvertierung je gefundener Spec (AC4)
Für jede vom Detect-Schritt gemeldete Spec, **einzeln und isoliert** (E1 — ein Fehlschlag darf den Gesamtlauf nicht stoppen):

1. **Original lesen** (`Read`) — vollständiger Inhalt, inkl. Frontmatter.
2. **Restrukturieren** — die Skill-Session selbst ist hier "der konvertierende Agent" aus dem Vertrag (§6) — kein Task-Dispatch, keine neue `agents/`-Datei. Inhalt **verlustfrei** in die Abschnitts-Struktur der aktuellen Vorlage (`templates/_docs/specs/_template.md`) überführen:
   - Frontmatter: `id`/`title`/`status`/`version` unverändert übernehmen; `spec_format` auf den Vorlagenwert **neu stempeln**.
   - Bestehende Abschnitte auf die nächstliegende Vorlagen-Überschrift mappen (`## Zweck`, `## Main Success Scenario` *(optional, nur falls im Original vorhanden oder sinnvoll ableitbar)*, `## Alternative Flows` *(optional)*, `## Acceptance-Kriterien`, `## Verträge`, `## Edge-Cases & Fehlerverhalten`, `## NFRs`, `## Nicht-Ziele`, `## Abhängigkeiten`). Inhalt, der keiner Vorlagen-Überschrift sauber zuzuordnen ist, wird unter der inhaltlich nächsten Überschrift **angehängt** statt verworfen (lossless-first, kein hübsches Wegkürzen).
   - **AC-Nummern bleiben stabil** (Vorlage: „AC-IDs sind stabil — nicht umnummerieren"). Reine Format-/Reihenfolge-Anpassung, **keine** inhaltliche Umdeutung der Kriterien.
3. **Schreiben** (`Write`/`Edit`) — derselbe Pfad, restrukturierter Inhalt.
4. **Verifizieren** (Pflicht vor Übernahme — Lossless-Garantie mechanisch absichern):
   - `spec_format` der neu geschriebenen Datei == Vorlagenwert (erneuter Lauf von `reconcile-stage1-detect.sh` meldet die Datei NICHT mehr).
   - Pflicht-Abschnitte vorhanden: `## Zweck`, `## Acceptance-Kriterien`, `## Verträge`, `## Edge-Cases & Fehlerverhalten`, `## Nicht-Ziele`, `## Abhängigkeiten`.
   - **AC-Mengen-Gleichheit:** die Menge der `AC<n>`-Token im Original == die Menge im konvertierten Text (`grep -oE 'AC[0-9]+'`, als Set vergleichen) — keine AC verloren, keine erfunden.
   - **Grobe Inhalts-Untergrenze:** Zeichenzahl der konvertierten Datei ≥ 60 % der Original-Zeichenzahl (Heuristik gegen versehentliches Abschneiden; stilistisches Straffen ist erlaubt, Halbieren-oder-mehr ist verdächtig).
5. **Bei Verifikations-Fehlschlag (E1):** `git checkout -- <pfad>` (Revert auf Original — die Spec bleibt unverändert), die Spec auf die **Nicht-konvertiert-Liste** für den Skill-Output/PR-Bericht setzen, **weiter** mit der nächsten Spec (kein Abbruch des Gesamtlaufs).
6. **Bei Erfolg:** Pfad + Ziel-Version auf die **Konvertiert-Liste** setzen (für §1c/Logbuch).

### 1c. Logbuch (AC5/AC10/AC11)
Nur für **tatsächlich konvertierte** Specs (AC11 — „Block enthält nur die getroffenen Änderungen"; nicht-konvertierte Specs sind **keine** Änderung und erscheinen **nicht** im Logbuch, sondern nur im PR-/Skill-Bericht, s. §1b.5):
```
scripts/spec-audit-append.sh \
  "Spec <pfad-1> auf <ziel-version> konvertiert" \
  "Spec <pfad-2> auf <ziel-version> konvertiert" \
  …
```
Ist die Konvertiert-Liste leer (alle Kandidaten sind an E1 gescheitert oder es gab von vornherein keine Kandidaten), wird `spec-audit-append.sh` **nicht** aufgerufen — kein leerer Block (AC11).

## 2. Stufe 2 (Inhalt) — NUR Vorbedingungs-Check, KEINE Implementierung (AC6, Rest = S-012)
**Noch nicht gebaut** (folgt in `docs/specs/reconcile.md` AC6–AC9 als Folge-Item S-012). Dieser Skill-Stand führt **ausschließlich** den Kanban-Gate-Check aus den Vertrag (§3) als Information aus, damit der Aufruf nicht ins Leere läuft:

- Prüfe via `scripts/board list --type story --status "<Status>"` für jede der vier Spalten `To Do` / `In Progress` / `Blocked` / `In Review` (leeres JSON-Array `[]` = Spalte leer): sind **alle vier** leer?
  - **Nein:** Ausgabe „Stufe 2 übersprungen — erst Board leerräumen" (AC6/A1). Kein Inhalts-Abgleich, kein Audit-Dispatch.
  - **Ja:** Ausgabe „Stufe 2 (Inhalt) ist in diesem Stand noch nicht implementiert — siehe `docs/specs/reconcile.md` AC6–AC9, geplant für S-012. Kanban ist leer, Vorbedingung wäre erfüllt." **Kein** `reviewer`-Audit-Dispatch, **kein** automatischer Doku-Nachzug — das ist bewusst außerhalb des Scopes dieses Items (kein Gold-Plating über AC1–AC5 hinaus).

## 3. Freigabe — EIN Diff (AC1/AC5)
Nur falls §1b mindestens eine Spec erfolgreich konvertiert hat (sonst: nichts zu landen, Lauf endet hier mit „keine Form-Drift gefunden").

- **`merge_policy: pr`:** neuer Branch `reconcile/stage1-<YYYY-MM-DD>` ab `default_branch`; **ein** Commit mit allen konvertierten Specs + dem `docs/spec-audit.md`-Block (`git add docs/specs/<konvertierte-pfade> docs/spec-audit.md`); Push; `gh pr create` gegen `default_branch` mit Body: Liste der konvertierten Specs (alt-Version → neu-Version) + ggf. die Nicht-konvertiert-Liste aus §1b.5 mit Kurzgrund. **Kein Self-Merge** — Freigabe ist Mensch-Gate (analog `train`/`retro`-PR-Mechanik).
- **`merge_policy: direct`:** **kein** Commit — die Änderungen bleiben unstaged im Working-Tree als reiner Diff zur Durchsicht (`git diff`). Output nennt explizit, dass nichts committet wurde und der User den Diff selbst prüft/committet.

## Output
```
Stufe 1: <N> Spec(s) konvertiert, <M> nicht-konvertiert (E1)
  Konvertiert: <pfad> (<alt> -> <neu>), …
  Nicht-konvertiert: <pfad> (<grund>), …
Stufe 2: <übersprungen — Board nicht leer | Kanban leer, Implementierung folgt in S-012>
Diff: <PR-Link | "Working-Tree-Diff, nicht committet (merge_policy: direct)" | "keine Drift gefunden — nichts zu tun">
```

## Grenzen (HART)
- Editiert **ausschließlich** `docs/specs/*.md` (Stufe 1) + `docs/spec-audit.md` (Logbuch) — kein App-Code, keine Board-Status-Änderung.
- **Kein** eigener `reconcile`-Agent, **kein** Task-Dispatch für die Konvertierung — die Skill-Session restrukturiert selbst (AC1, Vertrag §7).
- **Kein** Self-Merge des eigenen PRs (`merge_policy: pr`) — Mensch-Gate Pflicht.
- Stufe 2 bleibt in diesem Stand ein **Vorbedingungs-Check ohne Wirkung** — kein Audit-Dispatch, kein automatischer Inhalts-Nachzug (das ist S-012, nicht dieses Item — `coder/R01`).
