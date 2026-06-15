# Board-Cut-Runbook — GitHub-Board → File-Board (Big-Bang-Migration)

> **Zweck.** Dieses Runbook konkretisiert `docs/architecture/board-subsystem.md §10`
> und beschreibt den einmaligen, reproduzierbaren Schnitt von einem GitHub Project v2
> auf das File-basierte Board (`board/`). Es ist reine Doku — es führt den Cut nicht
> selbst aus.
>
> **Spec.** `docs/specs/board-github-export.md` — AC8 (Runbook [0]–[5]), AC9 (Rollback).
>
> **Reihenfolge.** Zuerst `dev-gui` (Dogfooding), dann ein kleines Projekt, dann der Rest.

---

## Voraussetzungen (einmalig, vor dem ersten Cut)

Bevor das Runbook für ein Repo ausgeführt wird, müssen folgende Artefakte
**projektübergreifend** vorhanden und funktionsfähig sein:

- `scripts/board` — CLI mit allen Verben (feature add, story add, set, show, list, next, rollup, lint, export-github).
- `scripts/board-lint.sh` — Lint-Skript (Exit 0 = grün; STORY-UNSPEC-WARN ist ok).
- `scripts/board-github-export` — Export-Skript (AC1–AC7, AC10).
- `gh` (GitHub CLI) — authentifiziert und auf die relevante Org/Repo konfiguriert.
- `python3` mit `PyYAML` — Abhängigkeit des Export-Skripts.
- Die Agents/Skills (`flow`, `requirement`, `coder`, usw.) sind auf das File-Backend
  umgestellt (`flow-board-backend`-Spec implementiert, getestet, gelandet).

---

## [0] Voraussetzung: File-Backend getestet und gelandet

**Was.** Das File-Backend (`flow-board-backend`) muss vor dem Cut vollständig
implementiert und in den Default-Branch gemergt sein. Erst dann ist der Cut sicher.

**Prüfpunkt.**

```bash
# board-CLI smoke: gibt S-001 o.ä. aus (oder leer wenn kein Board da)
scripts/board next

# board lint: muss auf einem bestehenden board/ Exit 0 liefern
scripts/board lint board/
```

Der Cut darf **nicht** mit einem halb-fertigen File-Backend durchgeführt werden —
ein Rollback nach Schritt [4] setzt `profile.md` auf die Board-Nummer zurück und
erwartet, dass der `gh`-Pfad wieder funktioniert (Rollback-Abschnitt unten).

---

## [1] Export: `board export-github` ausführen

**Was.** Das Export-Skript liest das aktuelle GitHub Project v2 (Issues, Status,
Priority, Labels, `Spec:`/`implements:`/`depends:`-Marker im Body) und schreibt
`board/features/` + `board/stories/` + `board/board.yaml`.

**Wann.** Kurz vor dem Cut, wenn das Board in einem stabilen Zustand ist (keine
laufenden Items, die gleichzeitig im GitHub-Board bearbeitet werden).

**Befehl.**

```bash
# Standard-Lauf: Projekt-Nummer aus .claude/profile.md
scripts/board export-github

# Explizite Angabe (wenn mehrere Orgs):
scripts/board export-github --org <github-org> --project <nummer>

# Probelauf ohne Schreiben:
scripts/board export-github --dry-run
```

**Was das Skript tut.**

1. Liest `board:` aus `.claude/profile.md` — ist der Wert `file`, bricht das Skript
   ab (`kein GitHub-Board zu exportieren`).
2. Lädt alle Issues des GitHub Project v2 via `gh project item-list` + `gh issue view`.
3. Bildet Auto-Features: je referenzierter Spec-Datei (`Spec:`-Marker), ersatzweise
   je Label-Cluster, Rest in ein `misc`-Feature.
4. Schreibt `board/features/F-###-*.yaml`, `board/stories/S-###-*.yaml`,
   `board/board.yaml` — atomar (Staging-Verzeichnis + `mv`).
5. Führt `board lint` intern aus und gibt das Ergebnis im Lauf-Report aus.

**Prüfpunkt nach dem Lauf.**

```
board/
  board.yaml          # schema_version: 1, project_slug: <repo-name>, Zähler
  features/           # F-001-*.yaml … F-00n-*.yaml
  stories/            # S-001-*.yaml … S-00n-*.yaml
```

Der Export gibt am Ende einen Report aus:

```
features: 4   stories: 27
clusters:  provisioning(8) · metrics(11) · secrets(6) · misc(2)
warnung:   depends #99 → kein Export-Item (verworfen, Story S-017)
lint:      GREEN
```

**Exit 0 + `lint: GREEN` ist die Mindestbedingung für Schritt [2].**

---

## [2] Lint grün

**Was.** `board lint` prüft die Integrität aller exportierten Dateien:
Parent-Existenz, `depends`-Auflösbarkeit, AC-Integrität, ID-Eindeutigkeit, Pflichtfelder.

**Befehl.**

```bash
scripts/board lint board/
```

oder via CLI-Verb:

```bash
scripts/board lint
```

**Erwartetes Ergebnis.** Exit 0. Warnungen (`STORY-UNSPEC-WARN`, z. B. bei Stories
ohne `implements`-Marker) sind akzeptabel — Fehler (`FIELD-REQUIRED`, `REF-BROKEN`,
`ENUM-INVALID`) sind es nicht.

**Wenn Lint rot.**

Lint-Fehler vor dem Cut-PR beheben:

- `FIELD-REQUIRED` bei `spec` oder `implements` — der Export schreibt Platzhalter
  (`FIXME — kein Spec:-Marker im Issue`); Owner kann diese vor dem PR durch echte
  Werte ersetzen oder im Cut-PR-Review nacharbeiten.
- `REF-BROKEN` bei `depends` — das Export-Skript hat nicht auflösbare Referenzen
  verworfen; falls Fehler auftreten, `board/stories/*.yaml` manuell prüfen.
- `ENUM-INVALID` bei `status` oder `priority` — Status-Mapping überprüfen;
  unbekannte GitHub-Status landen auf `To Do` (Warnung, kein Fehler).

Nach manuellem Fix erneut `scripts/board lint board/` ausführen bis Exit 0.

---

## [3] Review-PR „Board → Files"

**Was.** Alle exportierten Dateien werden als ein git-Commit gebündelt und als PR
eingestellt. Der Owner prüft Feature-Bildung, `depends`-Ketten und Story-Zuordnung.

**Befehl.**

```bash
# Export-Dateien stagen
git add board/

# Commit (einmaliger Import-Commit, kein Squash nötig)
git commit -m "board: GitHub-Export (Migration [1]–[2])"

# PR erstellen
gh pr create \
  --title "Board → Files (Big-Bang-Migration)" \
  --body "$(cat <<'EOF'
## Was

Einmaliger Export des GitHub Project v2 nach board/.
Migrationsschritt [1]–[2] aus docs/architecture/board-cut-runbook.md.

## Review-Checkliste

- [ ] Feature-Bildung sinnvoll (Spec-Cluster / Label-Cluster)?
- [ ] depends-Ketten korrekt auf S-### aufgelöst?
- [ ] Offensichtlich falsch zugeordnete Stories umhängen (parent-Feld)?
- [ ] `goal`-Platzhalter der Features durch echte Ziele ersetzen?
- [ ] Lint grün? (board-lint.sh board/ → Exit 0)
EOF
)"
```

**Owner-Aufgaben im Cut-PR.**

- Features umbenennen / Goals ausfüllen (die Export-Heuristik setzt Platzhalter).
- Stories zwischen Features umhängen wenn die Cluster-Zuordnung nicht stimmt.
- `FIXME`-Platzhalter bei `spec` / `implements` durch echte Werte ersetzen wo möglich.
- `board rollup --all` ausführen und das Ergebnis in den Commit aufnehmen (optional,
  aktualisiert `progress`-Felder der Features).

**Prüfpunkt.** Der PR ist bereit zum Mergen, wenn:

- `board lint board/` → Exit 0 (kein Fehler, Warnungen ok)
- Mindestens eine Review-Runde (Owner hat Feature-Bildung + depends geprüft)

---

## [4] Cut: PR mergen + Profil umstellen + GitHub-Board archivieren

**Was.** Der Cut-PR wird gemergt, das Profil umgestellt und das GitHub-Board als
Archiv eingefroren. Ab diesem Moment ist das File-Board die einzige aktive Quelle.

**Schritt 4a — PR mergen.**

```bash
# PR-Nummer aus gh pr list entnehmen
gh pr merge <pr-nummer> --merge
```

**Schritt 4b — `profile.md` auf `board: file` umstellen.**

```bash
# .claude/profile.md: board: <nummer> → board: file
# Direkt editieren (einzeilige Änderung):
sed -i '' 's/^board: [0-9]*/board: file/' .claude/profile.md

# Prüfen:
grep "^board:" .claude/profile.md
# Erwartete Ausgabe: board: file

# Committen:
git add .claude/profile.md
git commit -m "profile: board: file (Cut abgeschlossen)"
git push
```

**Schritt 4c — GitHub-Board archivieren (NICHT löschen).**

Das archivierte Board ist die Rückfallebene. Es darf unter keinen Umständen
gelöscht werden — ein `git revert` des Cut-PR + Profil-Rückstellung reicht
als Rollback genau dann, wenn das Board noch im GitHub-Archiv erreichbar ist.

```bash
# GitHub Project v2 schließen/archivieren (read-only setzen):
# Über die GitHub-Web-UI:
#   GitHub → Organisation → Projects → <Projekt-Name> → Settings → Archive project
#
# Oder via gh CLI (falls unterstützt):
gh project close <nummer> --owner <org>
```

**Wichtig:** „Archivieren" = Project auf `closed`/`archived` setzen, nicht `delete`.
Alle Issues und Kommentare bleiben erhalten. Das Board ist danach read-only sichtbar.

**Prüfpunkt nach Schritt [4].**

```bash
# File-Backend aktiv?
grep "^board:" .claude/profile.md   # board: file

# Nächste bereite Story aus File-Backend:
scripts/board next                  # gibt JSON mit Story-ID aus (oder leer)

# Export-Schutz aktiv (zweiter Export würde abbrechen):
scripts/board export-github         # Erwartung: "kein GitHub-Board zu exportieren"
```

---

## [5] dev-gui-Aggregator aktivieren

**Was.** Der `dev-gui`-Board-Aggregator wird auf die Repo-Wurzeln konfiguriert und
gestartet. Er liest `board/`-Ordner aus allen registrierten Repos und zeigt eine
projektübergreifende Übersicht.

Dieser Schritt ist eine eigene Spec (`dev-gui-board-aggregator`) und wird hier nur
als Runbook-Abschluss erwähnt. Konkrete Befehle: siehe dortige Spec/Doku.

**Prüfpunkt.**

- `dev-gui` zeigt das migrierte Repo unter `Projekt → Feature → Story`.
- Feature-Rollup (progress-Balken) korrekt berechnet.
- Status-Änderungen via `scripts/board set` erscheinen nach Re-Scan in der Übersicht.

---

## Rollback-Pfad (AC9)

**Wann Rollback.** Der Rollback ist nötig, wenn nach dem Cut schwerwiegende Probleme
auftreten — z. B. Agents können Stories nicht lesen, `board next` gibt Fehler zurück,
oder der Cut-PR hat strukturell falsche Daten eingecheckt.

**Voraussetzung für Rollback.** Das GitHub-Board muss archiviert (nicht gelöscht) sein.
Ist es gelöscht, ist der `gh`-Pfad nicht mehr herstellbar und der Rollback scheitert.

### Rollback-Schritte

**Schritt R1 — Cut-PR revertieren.**

```bash
# Commit-SHA des Merge-Commits des Cut-PR ermitteln:
git log --oneline -5

# Revert (erzeugt einen neuen Commit, kein force-push):
git revert <merge-commit-sha>
git push
```

Der Revert entfernt `board/features/`, `board/stories/`, `board/board.yaml`
aus dem Working-Tree. Das Repo ist wieder im Zustand vor dem Export.

**Schritt R2 — `profile.md` zurück auf die Board-Nummer.**

```bash
# .claude/profile.md: board: file → board: <ursprüngliche-nummer>
# Beispiel für agent-flow (Board #5):
sed -i '' 's/^board: file/board: 5/' .claude/profile.md

# Prüfen:
grep "^board:" .claude/profile.md
# Erwartete Ausgabe: board: 5

# Committen:
git add .claude/profile.md
git commit -m "profile: Rollback — board: <nummer> (Revert Cut)"
git push
```

**Schritt R3 — GitHub-Board reaktivieren.**

```bash
# GitHub Project v2 aus dem Archiv-Status zurücksetzen:
# Über die GitHub-Web-UI:
#   GitHub → Organisation → Projects → <Projekt-Name> (Archived) → Reopen project
#
# Oder via gh CLI:
gh project close <nummer> --owner <org> --undo
```

**Schritt R4 — Prüfen.**

```bash
# gh-Pfad wieder aktiv?
gh project item-list <nummer> --owner <org> --limit 5

# board next liefert leere Ausgabe (kein File-Board mehr)?
scripts/board next   # Erwartung: leere Ausgabe (board/ existiert nicht mehr)

# profile.md korrekt?
grep "^board:" .claude/profile.md   # board: <nummer>
```

### Was der Rollback sichert und was nicht

| Was | Gesichert? | Bemerkung |
|---|:---:|---|
| GitHub-Issue-Daten (Status, Body, Labels) | Ja | Archiviertes Board ist vollständig |
| Kommentare auf Issues | Ja | Archiv enthält alle Kommentare |
| Status-Änderungen die NACH dem Cut im File-Board gemacht wurden | Nein | Nur git-revert, kein Sync zurück nach GitHub |
| `board/`-Dateien nach Revert | Nein (gewollt) | Revert entfernt sie aus dem Repo |

**Empfehlung:** Rollback so früh wie möglich — je mehr Status-Änderungen im
File-Board nach dem Cut gemacht wurden, desto mehr manuelle Nacharbeit ist nötig
um das GitHub-Board wieder auf den neuesten Stand zu bringen.

---

## Kurzreferenz (alle Schritte auf einen Blick)

```
[0] Voraussetzung
    • scripts/board + Agents/Skills auf File-Backend (PR gemergt, getestet)
    • gh CLI authentifiziert
    Prüfpunkt: scripts/board next (Exit 0)

[1] Export
    scripts/board export-github [--dry-run]
    Prüfpunkt: board/ befüllt, Lauf-Report: lint: GREEN, Exit 0

[2] Lint grün
    scripts/board lint board/
    Prüfpunkt: Exit 0 (STORY-UNSPEC-WARN ok, Fehler → beheben)

[3] Review-PR "Board → Files"
    git add board/ && git commit -m "board: GitHub-Export (Migration [1]–[2])"
    gh pr create ...
    Prüfpunkt: Owner hat Feature-Bildung + depends geprüft; lint: grün

[4] Cut
    4a. gh pr merge <pr-nummer> --merge
    4b. profile.md: board: file  +  git commit + push
    4c. GitHub-Board: ARCHIVIEREN (nicht löschen)
    Prüfpunkt: board: file im Profil, board next liefert Story, export-github bricht ab

[5] dev-gui-Aggregator aktivieren
    (siehe dev-gui-board-aggregator-Spec)
    Prüfpunkt: Projekt in dev-gui Übersicht sichtbar

ROLLBACK (jederzeit nach [4]):
    R1. git revert <merge-commit-sha> + push
    R2. profile.md: board: <nummer>  +  git commit + push
    R3. GitHub-Board aus Archiv reaktivieren
    R4. gh project item-list <nummer> (Prüfpunkt)
```
