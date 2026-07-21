---
pack: build/uv
pack_version: 1.0
pack_date: 2026-07-21
primary_sources:
  - https://docs.astral.sh/uv/
  - https://docs.astral.sh/uv/guides/projects/
  - https://docs.astral.sh/uv/concepts/projects/layout/
  - https://docs.astral.sh/uv/concepts/projects/dependencies/
  - https://docs.astral.sh/uv/concepts/projects/sync/
  - https://docs.astral.sh/uv/guides/integration/docker/
non_sources: [dev.to, medium.com, stackoverflow.com, geeksforgeeks.org, realpython.com]
---

# Knowledge Pack: uv

Astral `uv` — Python-Package-/Project-Manager (Rust), ersetzt pip/pip-tools/pipx/poetry/pyenv/virtualenv als eine Toolchain. Geladen bei `profile.build: uv`. Regel-IDs: `uv/A<NN>` · `uv/B<NN>` · `uv/C<NN>`.

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land). Schreibt: `agent-flow:train`. Nicht ändern ohne `/train build/uv`-Lauf.

- `uv/A01` — **`uv init` erzeugt das Projekt-Skelett** (`pyproject.toml`, `main.py`/`src/`-Layout, `.python-version`, `.gitignore`, `README.md`). `pyproject.toml` startet minimal mit `[project]` (`name`, `version`, `dependencies = []`). [src: https://docs.astral.sh/uv/guides/projects/]
- `uv/A02` — **`uv add <pkg>` / `uv remove <pkg>` schreiben `pyproject.toml` UND `uv.lock` in einem Schritt.** Versions-Constraints (`uv add 'requests==2.31.0'`) und VCS-Quellen (`uv add git+https://...`) werden direkt unterstützt; Migration aus `requirements.txt` via `uv add -r requirements.txt -c constraints.txt`. [src: https://docs.astral.sh/uv/guides/projects/]
- `uv/A03` — **`uv.lock` ist ein *universelles* (cross-platform) Lockfile** — es kapselt die auflösbaren Pakete über alle Python-Marker/Plattformen hinweg, nicht nur die des Erstell-Rechners. Es ist zwar human-readable TOML, aber laut Doku **nicht manuell editierbar** — Format ist uv-intern, nicht kompatibel mit anderen Tools. **Pflicht: ins Repo committen** — „should be checked into version control, allowing for consistent and reproducible installations across machines". [src: https://docs.astral.sh/uv/concepts/projects/layout/]
- `uv/A04` — **`uv run` verifiziert vor jeder Ausführung, dass das Lockfile zu `pyproject.toml` passt** (Auto-Lock+Sync) — kein manuelles `uv sync` vor jedem `uv run` nötig im Dev-Workflow. [src: https://docs.astral.sh/uv/guides/projects/]
- `uv/A05` — **`uv sync --locked` vs. `--frozen` sind NICHT austauschbar.** `--locked` validiert das Lockfile gegen `pyproject.toml` und bricht mit Fehler ab, falls veraltet (kein Auto-Update) — richtig für CI/Deploy. `--frozen` überspringt die Validierung komplett und nutzt das Lockfile as-is — richtig für reine Reproduktion eines bereits geprüften Zustands (z.B. zweiter Docker-Layer). CI-Muster: früh `uv lock --check` (Äquivalent zu `--locked`, prüft ohne zu installieren), danach Install mit `uv sync --locked`. [src: https://docs.astral.sh/uv/concepts/projects/sync/]
- `uv/A06` — **Dependency Groups nach PEP 735 (`[dependency-groups]`-Tabelle), nicht `[project.optional-dependencies]`.** `uv add --dev pytest` erzeugt/erweitert die Gruppe `dev`; `uv add --group lint ruff` erzeugt beliebige weitere Gruppen. Dependency-Groups sind lokal (Dev/Test/Lint) und werden NICHT mit dem Package auf PyPI veröffentlicht — für öffentlich installierbare Extras bleibt `[project.optional-dependencies]` (PEP 621) zuständig (`uv add httpx --optional network`). `uv sync` kennt `--all-groups`, `--no-dev`, `--group <name>`, `--no-group <name>`, `--no-default-groups`. Legacy: existiert bereits `[tool.uv] dev-dependencies`, nutzt `uv add --dev` weiterhin diese Sektion statt `[dependency-groups].dev` neu anzulegen. [src: https://docs.astral.sh/uv/concepts/projects/dependencies/]
- `uv/A07` — **Docker: uv-Binary per `COPY --from=ghcr.io/astral-sh/uv:<version> /uv /uvx /bin/` beziehen, NICHT `:latest`.** Offizielle Doku empfiehlt explizit das Pinnen auf eine konkrete Version (oder SHA256-Digest) für reproduzierbare Builds — `:latest` unterläuft genau die Reproduzierbarkeit, die `uv.lock` sonst garantiert. [src: https://docs.astral.sh/uv/guides/integration/docker/]
- `uv/A08` — **Docker-Multi-Stage-Pattern mit Layer-Caching: Dependencies VOR Projekt-Code installieren.** Kanonisches Muster: `RUN --mount=type=cache,target=/root/.cache/uv --mount=type=bind,source=uv.lock,target=uv.lock --mount=type=bind,source=pyproject.toml,target=pyproject.toml uv sync --locked --no-install-project`, danach erst `COPY . /app` gefolgt von `uv sync --locked --no-editable`. `--no-install-project` installiert nur die Dependencies, nicht das Projekt selbst — Docker-Layer-Cache bleibt bei reinen Code-Änderungen (ohne Dependency-Änderung) warm. Finale Runtime-Stage kopiert nur `.venv` aus der Builder-Stage (`COPY --from=builder /app/.venv /app/.venv`). [src: https://docs.astral.sh/uv/guides/integration/docker/]
- `uv/A09` — **`uv pip install --system` ist der pip-kompatible Pfad OHNE projektbezogenes venv** — für Container, die bewusst kein `uv sync`/kein Projekt-Environment wollen (z.B. Tool-Installation im System-Python via `ENV UV_SYSTEM_PYTHON=1` + `uv pip install --system <pkg>`). Für normale Projekt-Container ist `uv sync` (mit `.venv`) der empfohlene Pfad, nicht `uv pip install --system` — Letzteres ist der explizite pip-Drop-in, nicht der projektbasierte Standardweg. [src: https://docs.astral.sh/uv/guides/integration/docker/]
- `uv/A10` — **`uv sync` und `uv run` synchronisieren standardmässig unterschiedlich streng.** `uv sync` ist per Default „exact" — es entfernt Pakete, die nicht im Lockfile stehen: „`uv sync` performs \"exact\" syncing by default, which means it will remove any packages that are not present in the lockfile" (nur mit `--inexact` beibehalten). `uv run` ist per Default „inexact" — es installiert fehlende Pakete nach, entfernt aber KEINE überzähligen Pakete: „`uv run` uses \"inexact\" syncing by default, ensuring that all required packages are installed but not removing extraneous packages" (nur mit `--exact` erzwingbar). Folge: ein manuell/ausserhalb von uv installiertes Extra-Paket verschwindet unter `uv sync`, überlebt aber unter reinem `uv run`-Workflow — Reproduzierbarkeits-Drift bleibt dort unentdeckt. Schärft `uv/A04`. [src: https://docs.astral.sh/uv/concepts/projects/sync/#handling-of-extraneous-packages]
- `uv/A11` — **Welche Dependency-Groups standardmässig mitinstalliert werden (bei `uv run`/`uv sync`), ist über `[tool.uv] default-groups` konfigurierbar** (Default: nur `dev`, laut Doku „By default, uv includes the `dev` dependency group in the environment"). `default-groups = ["dev", "foo"]` erweitert die Default-Menge additiv, `default-groups = "all"` aktiviert alle Gruppen. Pro Aufruf lässt sich das Default-Verhalten weiterhin mit `--no-default-groups` (alle) bzw. `--no-group <name>` (einzelne Gruppe) übersteuern. Ergänzt `uv/A06`. [src: https://docs.astral.sh/uv/concepts/projects/dependencies/#default-groups]
- `uv/A12` — **Die offiziellen abgeleiteten uv-Docker-Images (`ghcr.io/astral-sh/uv:<version>-<base>`, z.B. `-alpine`/`-bookworm`) setzen seit uv `0.8` zusätzlich `UV_TOOL_BIN_DIR=/usr/local/bin`** — laut Doku „starting with `0.8` each derived image also sets `UV_TOOL_BIN_DIR` to `/usr/local/bin` to allow `uv tool install` to work as expected with the default user". Relevant nur, wenn eines dieser abgeleiteten Images (nicht das distroless Binary-COPY-Pattern aus A07) als Basis dient UND zusätzlich Tools via `uv tool install` bereitgestellt werden sollen — ohne dieses Setting würde `uv tool install` beim Default-User des Images in ein nicht auf `PATH` liegendes Verzeichnis installieren. [src: https://docs.astral.sh/uv/guides/integration/docker/#available-images]

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Schreibt: `agent-flow:retro` ab ≥2 Projekten × ≥2 Stellen (siehe `docs/architecture/framework-build-subsystem.md` §9 Schutzgitter). Stand initial: leer — füllt sich, wenn Projekte real damit arbeiten.

_(noch keine Einträge; siehe Schutzgitter in der Spec)_

## C. Konventionen (Floor)

> Stabile Konventionen, manuell gepflegt (User-Approval Pflicht für Edits durch `train`/`retro`).

- `uv/C01` — **`uv.lock` immer committen**, `.venv/` NIE (uv legt automatisch ein internes `.gitignore` im `.venv` an, das es von Git ausschließt — dennoch explizit in Projekt-`.gitignore` festhalten).
- `uv/C02` — **Python-Version pinnen via `.python-version`** (von `uv init` erzeugt) statt implizit auf System-Python zu vertrauen — macht `uv run`/`uv sync` deterministisch bzgl. Interpreter-Version.

## Coder-Guidance

- Projekt-Setup: `uv init` → Dependencies mit `uv add <pkg>` (bzw. `uv add --dev <pkg>` für Test-/Lint-Tools) statt manuellem `pyproject.toml`-Edit + separatem `pip install` (A01/A02/A06).
- Ausführen/Testen im Projekt: `uv run <befehl>` statt manuellem venv-Aktivieren + `python`/`pytest` direkt — `uv run` hält Lockfile/Env automatisch synchron (A04).
- Dev-/Lint-/Test-Tools gehören in Dependency-Groups (`--dev`, `--group <name>`), NICHT in `[project.dependencies]` — sonst werden sie bei einer Package-Veröffentlichung an Endnutzer mitgezogen (A06).
- Docker: Multi-Stage-Pattern verwenden (Builder-Stage mit `uv sync --locked --no-install-project` vor `COPY . /app`, Runtime-Stage kopiert nur `.venv`) — nicht ein einzelnes `RUN uv sync` nach vollem `COPY .` (bricht Layer-Caching) (A08). uv-Version im `COPY --from=ghcr.io/astral-sh/uv:<version>` explizit pinnen, nicht `:latest` (A07).
- CI/Deploy: `uv sync --locked` (nicht plain `uv sync`) — verhindert stilles Lockfile-Update im Deploy-Pfad; Drift wird zum Fehler statt zur überraschten Runtime (A05).

## Reviewer-Checklist

- `uv.lock` fehlt im Repo (nicht committed) → **Critical** (A03, Reproducibility-Bruch).
- `.venv/` im Repo committed → **Important** (C01).
- Dev-/Test-/Lint-Only-Pakete (pytest, ruff, mypy, …) in `[project.dependencies]` statt `[dependency-groups]`/`--dev` → **Important** (A06, Bloat für Endnutzer-Installs).
- Dockerfile ohne Multi-Stage / mit `COPY . /app` VOR `uv sync` (kein Dependency-Layer-Cache) → **Suggestion** (A08, Build-Performance).
- Dockerfile mit `ghcr.io/astral-sh/uv:latest` statt gepinnter Version → **Important** (A07, Reproducibility).
- CI-Install-Schritt mit plain `uv sync` statt `uv sync --locked`/`uv lock --check` → **Important** (A05, verdecktes Lockfile-Drift-Risiko).

## Test-Approach

- Lockfile-Freshness-Gate (früh in CI, ohne Install): `uv lock --check`.
- Install/Sync (reproduzierbar, kein Auto-Update): `uv sync --locked`.
- Smoke-/Unit-Test-Befehl (kanonisch): `uv run pytest`.
- Nur-Dependencies-Sync ohne Projekt selbst installieren (Docker-Build-Layer): `uv sync --locked --no-install-project`.
