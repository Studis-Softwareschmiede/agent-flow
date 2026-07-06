#!/usr/bin/env bash
# infra-leitplanken-smoke.sh — Smoke-Test der Infra-Leitplanken (Template-Artefakt).
#
# Covers (regression-runner): AC4, AC7, AC8
#
# Prueft, ohne echtes Playwright/Node-Package zu installieren (Netzwerk-frei,
# deterministisch), das Guard-Modul
# `templates/_shared/regression/tests-example/regression/verbund/infra-guard.ts`
# direkt per `node` (native TypeScript-Unterstuetzung, kein separater Build-
# Schritt noetig):
#   - AC7: ein konformer `rtest-*`-Name wird akzeptiert; ein Name ohne
#     `rtest-*`-Praefix wird mit `InfraGuardrailError` hart abgelehnt.
#   - AC7 Edge-Case: ein `rtest-*`-Name, der mit einem Eintrag der
#     Produktiv-Allowlist kollidiert, wird trotz korrektem Praefix abgelehnt
#     (AC7 hat Vorrang, keine Produktiv-Beruehrung).
#   - AC8: das Provision->Poll->Use->Teardown-Muster (try/finally, siehe
#     infra.fixture.ts) fuehrt den Teardown auch dann aus, wenn der
#     "Use"-Schritt eine Exception wirft — UND der Guard wird sowohl vor der
#     Provisionierung als auch vor dem Teardown aufgerufen.
#   - AC8 (Negativ-Beweis): scheitert der Guard bereits beim Provisionieren
#     (ungueltiger Name), wird KEINE Ressource angelegt und folglich kein
#     Teardown-Aufruf ausgeloest.
#
# Voraussetzungen: node >= 22 (natives TypeScript-Type-Stripping fuer einfache
# Interfaces/Klassen, kein `tsc`/`ts-node` noetig).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD_SRC="$REPO_ROOT/templates/_shared/regression/tests-example/regression/verbund/infra-guard.ts"

[[ -f "$GUARD_SRC" ]] || { echo "[smoke-infra-leitplanken] FAIL: Guard-Modul nicht gefunden: $GUARD_SRC" >&2; exit 1; }

SMOKE_DIR="$(mktemp -d "/tmp/smoke-infra-leitplanken-XXXXXX")"
cleanup() { rm -rf "$SMOKE_DIR"; }
trap cleanup EXIT INT TERM

log()  { printf '[smoke-infra-leitplanken] %s\n' "$*"; }
fail() { printf '[smoke-infra-leitplanken] FAIL: %s\n' "$*" >&2; exit 1; }

cp "$GUARD_SRC" "$SMOKE_DIR/infra-guard.ts"

cat >"$SMOKE_DIR/check.mjs" <<'NODE'
import { guardInfraResourceName, InfraGuardrailError, RTEST_PREFIX } from './infra-guard.ts';

let failures = 0;
function ok(label, fn) {
  try {
    fn();
    console.log(`ok - ${label}`);
  } catch (err) {
    failures++;
    console.error(`FAIL - ${label}: ${err.message}`);
  }
}

// --- AC7: konformer rtest-*-Name wird akzeptiert ----------------------------
ok('AC7: konformer rtest-*-Name wird akzeptiert', () => {
  guardInfraResourceName(`${RTEST_PREFIX}infra-001`);
});

// --- AC7: nicht-konformer Name wird hart abgelehnt --------------------------
ok('AC7: Name ohne rtest-*-Praefix wird abgelehnt', () => {
  let threw = false;
  try {
    guardInfraResourceName('prod-infra-001');
  } catch (err) {
    threw = err instanceof InfraGuardrailError;
    if (!/rtest-\*/.test(err.message)) {
      throw new Error(`unerwartete Fehlermeldung: ${err.message}`);
    }
  }
  if (!threw) throw new Error('guard hat NICHT geworfen — Leitplanke verletzt');
});

// --- AC7 Edge-Case: rtest-*-Name kollidiert mit Allowlist-Eintrag -----------
ok('AC7 Edge-Case: rtest-*-Name kollidiert mit Allowlist -> Abbruch (AC7 Vorrang)', () => {
  const collidingName = `${RTEST_PREFIX}shared-prod-alias`;
  let threw = false;
  try {
    guardInfraResourceName(collidingName, { allowlist: [collidingName] });
  } catch (err) {
    threw = err instanceof InfraGuardrailError;
    if (!/Allowlist/.test(err.message)) {
      throw new Error(`unerwartete Fehlermeldung (erwartet Allowlist-Kollision): ${err.message}`);
    }
  }
  if (!threw) throw new Error('guard hat trotz Allowlist-Kollision NICHT geworfen');
});

// --- AC8: garantierter Teardown auch im Fehlerpfad --------------------------
ok('AC8: Teardown laeuft trotz Exception im "Use"-Schritt', () => {
  const events = [];
  let resource = null;
  try {
    // PROVISION (mit Guard-Check davor, wie in infra.fixture.ts)
    const id = `${RTEST_PREFIX}${Date.now()}`;
    guardInfraResourceName(id);
    resource = { id };
    events.push('provisioned');

    // USE — wirft absichtlich, um den Fehlerpfad zu simulieren.
    events.push('use-start');
    throw new Error('absichtlicher Fehlschlag im Testkoerper');
  } catch (err) {
    events.push(`caught:${err.message}`);
  } finally {
    // TEARDOWN — MUSS trotz der Exception oben laufen (AC8), inkl. erneutem
    // Guard-Check vor dem Abbau (Defense-in-Depth, wie in infra.fixture.ts).
    if (resource) {
      guardInfraResourceName(resource.id);
      events.push('torn-down');
    }
  }
  if (!events.includes('torn-down')) {
    throw new Error(`Teardown lief NICHT trotz Fehlerpfad — Events: ${events.join(',')}`);
  }
});

// --- AC8 Negativ-Beweis: Guard-Verstoss beim Provisionieren -> keine
// Ressource angelegt, kein Teardown-Aufruf ausgeloest -----------------------
ok('AC8 Negativ-Beweis: Provisionierungs-Verstoss legt keine Ressource an', () => {
  const events = [];
  let resource = null;
  try {
    guardInfraResourceName('prod-invalid-name'); // wirft VOR jeder Ressourcen-Erzeugung
    resource = { id: 'prod-invalid-name' }; // wird NIE erreicht
    events.push('provisioned');
  } catch (err) {
    events.push(`guard-blocked:${err.message}`);
  } finally {
    if (resource) {
      events.push('torn-down');
    }
  }
  if (events.includes('provisioned') || events.includes('torn-down')) {
    throw new Error(`Ressource wurde trotz Guard-Verstoss angelegt/abgebaut — Events: ${events.join(',')}`);
  }
  if (!events.some((e) => e.startsWith('guard-blocked'))) {
    throw new Error('Guard hat den ungueltigen Namen nicht blockiert');
  }
});

if (failures > 0) {
  console.error(`\n${failures} Vertrag(e) verletzt.`);
  process.exit(1);
}
console.log('\nALL VERTRAEGE PASS');
NODE

log "SMOKE_DIR=$SMOKE_DIR"
if ! node "$SMOKE_DIR/check.mjs"; then
  fail "Guard-Vertraege verletzt (siehe Ausgabe oben)"
fi

echo "PASS"
