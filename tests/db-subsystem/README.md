# `tests/db-subsystem/` — Smoke-Tests pro Dialekt

End-to-end-Smoke-Tests für das DB-Subsystem (Spec
[`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §13).
Geprüft werden pro Dialekt drei Verträge:

| Vertrag | Was wird verifiziert |
|---|---|
| **Apply** | Compose-Fragment + Migration-Runner + `000_init_meta` bringen die DB sauber hoch, eine Test-Migration (`001_smoke`) läuft durch, das Test-Datum ist über die Standard-CLI lesbar. |
| **Idempotenz** | Ein zweiter Aufruf von `run-migrations.sh` wendet nichts mehr an — die Marker-Tabelle/-Collection filtert alle Versionen (Spec §6). |
| **Drift** | Eine bereits applizierte Migration wird nachträglich editiert. Der Runner erkennt den SHA-256-Mismatch (Spec §16-R5) und reagiert: hard-fail (mysql, sqlite) oder DRIFT-Warning (postgres, mongodb). |

Die Tests stehen **außerhalb** des `/flow`-Loops — sie sind Selbsttests der
Fabrik vor jedem DB-Subsystem-Release und nach jedem Template-Edit.

## Voraussetzungen

- **Docker-Daemon** läuft (lokal oder Remote via `DOCKER_HOST`).
- **mind. 2 GB freier RAM** — `mongo:7` und `mariadb:11` sind die
  Schwergewichte; parallel starten würde 3-4 GB brauchen, deshalb läuft
  `run-all.sh` strikt sequenziell.
- **`docker compose`** v2 (das Plugin, nicht das alte `docker-compose`).
- Bash, `sha256sum`, `grep`, `sed` — alles im POSIX-Standard.

Kein lokales `psql`/`mysql`/`mongosh`/`sqlite3` nötig — die Smoke-Tests
nutzen ausschließlich Container-CLIs (über `docker compose exec` oder
einen Throwaway-Container bei sqlite).

## Ausführen

```bash
# Alle 4 Dialekte sequenziell (Default-Pfad vor Release)
./run-all.sh

# Einzelner Dialekt (z.B. nach Edit am postgres-Template)
./smoke-postgres.sh

# Mit explizitem Log-Verzeichnis (sonst /tmp/db-smoke-runs-XXXXXX)
LOG_DIR=/tmp/smoke-2026-05-31 ./run-all.sh
```

`run-all.sh` exit-Codes:

| Exit | Bedeutung |
|---|---|
| 0 | Alle 4 grün. |
| 1 | Mindestens ein Dialekt rot — Final-Output zeigt Log-Pfad + hint-Zeile. |

Einzel-Skripte loggen direkt nach stdout, schreiben **kein** Log-File —
`run-all.sh` macht das für sie.

## Wann ausführen

- **Vor jedem Release** des DB-Subsystems (Welle-2-Template-Bumps,
  Welle-3-Skill-Edits, die Templates konsumieren).
- **Nach jedem Edit** an `templates/_shared/db-<dialect>/` (Fragment,
  Runner, Init-Migration).
- **Nach jedem Edit** an `skills/preview/SKILL.md`, das den
  Migration-Apply-Path im `/preview up` ändert.
- **CI** (geplant Welle 3): GitHub-Actions-Workflow filtert auf die
  obigen Pfade und ruft `./run-all.sh` (Spec §13).

## Was die Tests NICHT prüfen

- **Pack-Inhalts-Korrektheit** (`knowledge/sql*.md`, `mongodb.md`) — das
  ist `reviewer`-Land und Mensch-Sache. Smoke-Tests prüfen nur die
  Mechanik (Runner, Marker, Idempotenz, Compose-Fragment).
- **Backup/Restore-Skripte** — eigene Test-Schicht (P2, nicht in P1
  Welle 3 enthalten).
- **End-to-end `/flow`-Simulation** — viel zu schwer für CI;
  Smoke-Tests bleiben auf die Template-Mechanik begrenzt (Spec §13
  „Annahme").

## Test-Aufbau (alle 4 Skripte identisch strukturiert)

1. `mktemp -d` → eindeutiges Test-Verzeichnis im `/tmp`.
2. Kopiere `compose.fragment.yml` + `db_scripts/000_init_meta.*` +
   `run-migrations.sh` aus dem Template ins Test-Verzeichnis.
3. Lege Test-Migration `db_scripts/001_smoke.<sql|js>` an: schlichte
   Tabelle/Collection `smoke` mit einer Zeile `(1, 'ok')`.
4. Schreibe `.env.db` mit Test-Credentials (`smoke-test-pw` etc.).
5. `docker compose up -d db` (außer sqlite — kein db-Service).
6. Warte auf Healthcheck.
7. `docker compose run --rm migrations` — Apply.
8. Verifiziere via CLI: 1 Zeile/Doc mit `(1, 'ok')`, Marker-Count = 2
   (000 + 001).
9. **Re-run** → erwartet alle SKIP, Marker-Count stabil.
10. **Drift**: editiere `001_smoke.*`, re-run → erwartet Drift-Reaktion
    (exit !=0 oder Output `DRIFT …` je nach Dialekt-Runner).
11. Cleanup über `trap`: `docker compose down -v --remove-orphans` +
    `rm -rf $TMPDIR`. Greift auch bei Fehler.

## Spec-Verweis

`docs/architecture/db-subsystem.md` §13 (Test-Verträge), §4
(Migrations-Konvention), §6 (Migration-Runner), §16-R4 (separates
migrations-Image), §16-R5 (optionale `checksum`-Spalte für Drift).
