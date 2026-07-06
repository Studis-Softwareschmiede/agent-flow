import { test, expect } from './infra.fixture';
import { guardInfraResourceName, InfraGuardrailError, RTEST_PREFIX } from './infra-guard';

/**
 * Covers (regression-playwright-conventions): AC4
 * Covers (regression-runner): AC4, AC7, AC8
 * @file Example tests using the infrastructure fixture + Infra-Leitplanken-Guard
 *
 * Demonstrates the guarantee that teardown runs even if a test fails (AC4/AC8),
 * and the `rtest-*`-Namensschema + Produktiv-Allowlist Leitplanken (AC7) that
 * `guardInfraResourceName` (./infra-guard.ts) durchsetzt.
 */

test('infrastructure chain with guaranteed teardown', async ({ infraResource }) => {
  // At this point, the resource has been provisioned and polled (status = 'ready').
  // The teardown will run automatically after this test, regardless of success/failure.

  expect(infraResource.status).toBe('ready');
  expect(infraResource.id).toMatch(/^rtest-\d+$/);

  // Simulate test assertion that might fail
  // If this throws, teardown still runs.
  expect(infraResource.createdAt).toBeInstanceOf(Date);
});

/**
 * Example: test that fails, but teardown still runs.
 * Uncomment to see teardown guarantee in action.
 */
// test('infrastructure chain with failure (teardown still runs)', async ({ infraResource }) => {
//   expect(infraResource.status).toBe('ready');
//   // This assertion will fail, but teardown still executes.
//   expect(infraResource.status).toBe('nonexistent-status');
// });

// --- AC7: rtest-*-Namensschema wird durchgesetzt -----------------------------

test('guard accepts a conforming rtest-* resource name', async () => {
  expect(() => guardInfraResourceName(`${RTEST_PREFIX}infra-001`)).not.toThrow();
});

test('guard rejects a resource name without the rtest-* prefix', async () => {
  expect(() => guardInfraResourceName('prod-infra-001')).toThrow(InfraGuardrailError);
});

// --- AC7 Edge-Case: rtest-*-Name kollidiert mit einem Allowlist-Eintrag ------
// (AC7 hat Vorrang — keine Produktiv-Beruehrung, selbst wenn der Name dem
// Testschema entspricht.)

test('guard rejects an rtest-* name that collides with an allowlist entry', async () => {
  const collidingName = `${RTEST_PREFIX}shared-prod-alias`;
  expect(() =>
    guardInfraResourceName(collidingName, { allowlist: [collidingName] })
  ).toThrow(InfraGuardrailError);
});

// --- AC8: garantiertes Cleanup auch im Fehlerpfad ----------------------------

test('teardown runs even when the test body throws (AC8)', async ({ infraResource }) => {
  expect(infraResource.id).toMatch(/^rtest-\d+$/);
  // Absichtlicher Abbruch: die Fixture-`finally`-Klausel (infra.fixture.ts)
  // ruft `teardownResource` trotzdem auf — beobachtbar an den `[infra]
  // Tearing down ...` / `[infra] Resource torn down ...`-Logzeilen, die auch
  // bei einem fehlschlagenden Testkoerper erscheinen.
  test.fail(true, 'Absichtlicher Fehlschlag zur Demonstration des garantierten Teardowns (AC8)');
  expect(infraResource.status).toBe('nonexistent-status');
});
