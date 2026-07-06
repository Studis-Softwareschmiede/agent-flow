#!/usr/bin/env bash
# run-regression.sh — Deterministischer Regressions-Runner (Template-Artefakt).
#
# Spec: docs/specs/regression-runner.md — deckt AC1, AC2, AC3, AC5, AC6, AC9
# direkt; AC4/AC7/AC8 (ephemeral-infra-Provisionierung, rtest-*-Namensschema,
# Produktiv-Allowlist, garantiertes Cleanup) per Delegation an den
# Fixture-/Infra-Leitplanken-Layer, den dieses Skript fuer den
# `ephemeral-infra`-Bucket aufruft (kein eigener Ressourcen-Code hier, s.u.).
#
# AC4/AC7/AC8 — dieses Skript provisioniert/zerstoert selbst NICHTS: fuer
#        `target: ephemeral-infra` ruft es lediglich `npx playwright test` auf
#        (s. `run_playwright "ephemeral-infra" ...` unten); die eigentliche
#        Provisionierung + der garantierte Teardown (AC4/AC8) sowie die
#        rtest-*-Namensschema-/Produktiv-Allowlist-Durchsetzung (AC7) leben in
#        der Playwright-Fixture, siehe Referenz-Implementierung:
#          templates/_shared/regression/tests-example/regression/verbund/infra-guard.ts
#          templates/_shared/regression/tests-example/regression/verbund/infra.fixture.ts
#        `infra-guard.ts` liefert `guardInfraResourceName()`, das vor JEDER
#        Provisionierung/JEDEM Teardown eines Infra-Ressourcennamens hart
#        abbricht, wenn der Name nicht `rtest-*` ist oder mit einem
#        Allowlist-Eintrag (produktive Ressource) kollidiert; das
#        Fixture-try/finally-Muster (regression-playwright-conventions.md AC4)
#        garantiert den Teardown-Aufruf auch im Fehlerpfad (AC8).
#
# AC1 — Deterministisch: dieses Skript dispatcht pro Testlauf KEINEN Agenten,
#        es ruft ausschliesslich `npx playwright test` auf.
# AC2/AC3/AC5 — Jede Suite deklariert ihr Testobjekt im Frontmatter der
#        Begleitbeschreibung (`<suite>.md`, `---\ntarget: local|ephemeral-infra|url\n---`).
#        Default fuer Bereichs-Suiten ist `local`; `url` ist optional waehlbar
#        (kein lokales Provisionieren).
# AC6 — Vor einem `local`-Lauf wird die Erreichbarkeit des lokal ausgerollten
#        Containers geprueft (Port aus `.claude/profile.md` `preview_port`,
#        Fallback: Host-Port-Mapping aus `docker-compose.yml`/`compose.yml`);
#        ist das Ziel nicht erreichbar, meldet der Runner einen klaren
#        Vorbedingungs-Fehler UND FUEHRT PLAYWRIGHT NICHT AUS (keine roten Tests).
# AC9 — Secrets werden, falls `scripts/load-env.sh` existiert (App-Secrets-
#        Subsystem, docs/architecture/secrets-subsystem.md), zur Laufzeit in
#        die Shell geladen und dadurch an den Playwright-Kindprozess vererbt.
#        Der Runner liest NIE Secrets aus Test-/Datendateien und persistiert
#        nichts (kein Schreiben von Klartext-Secrets auf die Platte).
#
# Usage:
#   scripts/run-regression.sh [<pfad-oder-datei> ...]   # Default: tests/regression
#
# Beispiele:
#   scripts/run-regression.sh                       # alle Suiten
#   scripts/run-regression.sh tests/regression/board # nur ein Bereich
#   scripts/run-regression.sh tests/regression/board/example.md
#
# Exit-Codes:
#   0   — alle angestossenen Playwright-Laeufe gruen
#   1   — Vorbedingungs-Fehler (target fehlt, local-Ziel nicht erreichbar, keine
#         Suiten gefunden) — kein/nicht-vollstaendiger Playwright-Lauf
#   >1  — Playwright-Exit-Code durchgereicht (rote Tests)
#
# Requires: bash (auch macOS-Systembash 3.2 kompatibel — keine assoziativen
#   Arrays), npx (Playwright als Dev-Dependency), curl (AC6).
#
# Bekannte Grenze: mischt ein Aufruf mehrere targets (z.B. local + url), werden
# die Reporter-Ausgabedateien (test-results/, playwright-report/) je Bucket
# sequenziell ueberschrieben — Report-Aggregation ueber mehrere Buckets ist
# NICHT Teil dieser Story (siehe Nicht-Ziele regression-runner.md).

set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
REGRESSION_ROOT="${APP_ROOT}/tests/regression"
PROFILE_FILE="${APP_ROOT}/.claude/profile.md"

err()  { printf '✗ %s\n' "$*" >&2; }
info() { printf 'ℹ %s\n' "$*"; }

# --- AC9: Secrets zur Laufzeit aus dem Credential-Store injizieren -----------
# Nie aus Test-/Datendateien lesen; keine Persistierung — load-env.sh schreibt
# kein Klartext-.env, sondern exportiert nur in die aktuelle (Kind-)Shell.
if [[ -f "${APP_ROOT}/scripts/load-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${APP_ROOT}/scripts/load-env.sh"
fi

# --- Suite-Discovery: Begleitbeschreibungen (<suite>.md) sammeln -------------
requested=("${@:-$REGRESSION_ROOT}")

md_files=()
for t in "${requested[@]}"; do
  if [[ -d "$t" ]]; then
    while IFS= read -r -d '' f; do md_files+=("$f"); done < <(find "$t" -type f -name '*.md' -print0 | sort -z)
  elif [[ "$t" == *.md && -f "$t" ]]; then
    md_files+=("$t")
  elif [[ -f "$t" ]]; then
    # <suite>.spec.ts direkt uebergeben -> zugehoerige Begleitbeschreibung ableiten
    cand="${t%.spec.ts}.md"
    if [[ -f "$cand" ]]; then
      md_files+=("$cand")
    else
      err "Keine Begleitbeschreibung fuer '$t' gefunden (erwartet: '$cand')."
      exit 1
    fi
  else
    err "Pfad nicht gefunden: '$t'"
    exit 1
  fi
done

if [[ ${#md_files[@]} -eq 0 ]]; then
  err "Keine Begleitbeschreibung (<suite>.md) unter '${requested[*]}' gefunden."
  exit 1
fi

# --- Frontmatter-Parser: `key: value` zwischen den ersten beiden '---'-Zeilen -
read_frontmatter_key() {
  local file="$1" key="$2"
  awk -v key="$key" '
    /^---[[:space:]]*$/ { delim++; next }
    delim==1 {
      if ($0 ~ "^"key":") {
        sub("^"key":[[:space:]]*", "");
        sub("[[:space:]]*#.*$", "");
        gsub(/[[:space:]]+$/, "");
        print;
        exit
      }
    }
    delim>=2 { exit }
  ' "$file"
}

# --- Bucketing nach target ----------------------------------------------------
# Hinweis: bewusst KEINE assoziativen Arrays (`declare -A`) — die erfordern
# Bash >= 4; macOS liefert /bin/bash weiterhin in Version 3.2 aus, und
# `#!/usr/bin/env bash` loest je nach PATH nicht garantiert eine neuere Bash
# auf. Statt einer Map wird der url-Bucket ueber zwei parallele indizierte
# Arrays gefuehrt (url_keys[i] <-> url_spec_lists[i]), die auch unter Bash 3.2
# funktionieren.
local_specs=()
infra_specs=()
url_keys=()
url_spec_lists=()

find_url_index() {
  # Setzt $url_index_result auf den Index von $1 in url_keys, oder -1.
  local needle="$1" i
  url_index_result=-1
  for i in "${!url_keys[@]}"; do
    if [[ "${url_keys[$i]}" == "$needle" ]]; then
      url_index_result="$i"
      return
    fi
  done
}

for md in "${md_files[@]}"; do
  spec="${md%.md}.spec.ts"
  if [[ ! -f "$spec" ]]; then
    err "Begleitbeschreibung ohne zugehoerige Testdatei: '$md' (erwartet '$spec')"
    exit 1
  fi

  target="$(read_frontmatter_key "$md" "target")"
  if [[ -z "$target" ]]; then
    err "Begleitbeschreibung ohne 'target' — '$md' (kein stillschweigender Default auf Produktiv-URL)."
    exit 1
  fi

  case "$target" in
    local)
      local_specs+=("$spec")
      ;;
    url)
      url="$(read_frontmatter_key "$md" "url")"
      if [[ -z "$url" ]]; then
        err "Suite '$md' deklariert 'target: url', aber kein 'url'-Feld im Frontmatter."
        exit 1
      fi
      find_url_index "$url"
      if [[ "$url_index_result" -eq -1 ]]; then
        url_keys+=("$url")
        url_spec_lists+=("$spec")
      else
        url_spec_lists["$url_index_result"]="${url_spec_lists[$url_index_result]} $spec"
      fi
      ;;
    ephemeral-infra)
      infra_specs+=("$spec")
      ;;
    *)
      err "Suite '$md' hat unbekanntes target '$target' (erwartet: local | ephemeral-infra | url)."
      exit 1
      ;;
  esac
done

overall_rc=0

run_playwright() {
  # $1 = Anzeigename, $2 = REGRESSION_BASE_URL (leer = unset), Rest = Spec-Dateien
  local label="$1" base_url="$2"
  shift 2
  info "Playwright-Lauf [$label]: ${*}"
  if [[ -n "$base_url" ]]; then
    REGRESSION_BASE_URL="$base_url" npx playwright test "$@"
  else
    npx playwright test "$@"
  fi
}

# --- local-Bucket: AC6 Vorbedingungs-Check vor jedem lokalen Lauf ------------
if [[ ${#local_specs[@]} -gt 0 ]]; then
  port=""
  if [[ -f "$PROFILE_FILE" ]]; then
    port="$(grep -E '^preview_port:' "$PROFILE_FILE" 2>/dev/null | head -1 | sed -E 's/^preview_port:[[:space:]]*//; s/[[:space:]]*#.*$//')"
  fi
  if [[ -z "$port" ]]; then
    for compose_file in "$APP_ROOT/docker-compose.yml" "$APP_ROOT/compose.yml" "$APP_ROOT/compose.yaml"; do
      [[ -f "$compose_file" ]] || continue
      port="$(grep -E '^\s*-\s*"?[0-9]+:[0-9]+"?\s*$' "$compose_file" 2>/dev/null | head -1 | sed -E 's/^[^0-9]*([0-9]+):[0-9]+.*/\1/')"
      [[ -n "$port" ]] && break
    done
  fi

  if [[ -z "$port" ]]; then
    err "local-Ziel: kein Port in '.claude/profile.md' (preview_port) oder Compose-Datei auffindbar — Vorbedingungs-Fehler."
    overall_rc=1
  else
    local_url="http://localhost:${port}"
    http_code="$(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' "${local_url}/" 2>/dev/null)" || true
    http_code="${http_code:-000}"
    if [[ "$http_code" == "000" ]]; then
      err "Ziel-Container '${local_url}' nicht erreichbar — zuerst 'cicd rollout'/Container starten."
      overall_rc=1
    else
      run_playwright "local" "$local_url" "${local_specs[@]}" || overall_rc=$?
    fi
  fi
fi

# --- url-Bucket: AC5 — kein lokales Provisionieren, keine Erreichbarkeits-Pruefung
for i in "${!url_keys[@]}"; do
  url="${url_keys[$i]}"
  # shellcheck disable=SC2206
  specs=(${url_spec_lists[$i]})
  run_playwright "url:${url}" "$url" "${specs[@]}" || overall_rc=$?
done

# --- ephemeral-infra-Bucket: kein REGRESSION_BASE_URL, Fixtures provisionieren selbst
if [[ ${#infra_specs[@]} -gt 0 ]]; then
  run_playwright "ephemeral-infra" "" "${infra_specs[@]}" || overall_rc=$?
fi

exit "$overall_rc"
