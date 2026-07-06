import { test as base } from '@playwright/test';
import { guardInfraResourceName, type InfraGuardOptions } from './infra-guard';

/**
 * @file Reference fixture for infrastructure chains
 *
 * Illustrates the Fabrik regression-test fixture pattern:
 * provision → poll → assert → teardown, with guaranteed teardown even on test failure.
 *
 * The teardown is guaranteed via Playwright's fixture `use()` pattern with try/finally.
 * Even if a test throws, the finally block runs.
 *
 * Infra-Leitplanken (regression-runner.md AC7/AC8): every resource name is
 * checked via `guardInfraResourceName` BEFORE it is provisioned AND again
 * before it is torn down — see `./infra-guard.ts`. A project that consumes
 * this template supplies its own production-resource allowlist via
 * `PRODUCTION_ALLOWLIST` below (empty by default: no known production
 * resources in this reference example).
 *
 * Usage: import { test } from './infra.fixture';
 */

// AC7 — Produktiv-Allowlist: Namen bestehender produktiver Ressourcen, die der
// Guard niemals antasten darf (auch nicht, falls sie zufaellig rtest-*
// heissen wuerden). Konsumierende Projekte befuellen diese Liste mit ihren
// echten Produktiv-Ressourcennamen; das Referenzbeispiel bleibt leer.
const PRODUCTION_ALLOWLIST: InfraGuardOptions = { allowlist: [] };

interface TestResource {
  id: string;
  status: string;
  createdAt: Date;
}

/**
 * Provision a test resource (e.g., ephemeral database, temporary service).
 * This is called once per test that uses the fixture.
 */
async function provisionResource(): Promise<TestResource> {
  console.log('[infra] Provisioning test resource...');
  // Simulate: allocate resource, set up test data, etc.
  const resourceId = `rtest-${Date.now()}`;

  // AC7 — Leitplanken-Check VOR jeder Provisionierung: bricht hart ab
  // (InfraGuardrailError), falls der Name gegen das rtest-*-Schema verstoesst
  // oder mit der Produktiv-Allowlist kollidiert. Wirft der Guard hier, wurde
  // noch keine Ressource angelegt — kein Teardown noetig.
  guardInfraResourceName(resourceId, PRODUCTION_ALLOWLIST);

  const resource: TestResource = {
    id: resourceId,
    status: 'provisioning',
    createdAt: new Date(),
  };

  // Simulate async provisioning (e.g., Docker container startup)
  await new Promise((resolve) => setTimeout(resolve, 100));
  resource.status = 'provisioned';
  console.log(`[infra] Resource provisioned: ${resource.id}`);
  return resource;
}

/**
 * Poll the resource to ensure it's ready (e.g., wait for DB to accept connections).
 */
async function pollResource(resource: TestResource, maxRetries = 10): Promise<void> {
  console.log(`[infra] Polling resource ${resource.id}...`);
  let retries = 0;
  while (retries < maxRetries) {
    // Simulate: check if resource is ready
    if (Math.random() > 0.3 || retries > 2) {
      resource.status = 'ready';
      console.log(`[infra] Resource ready after ${retries} polls`);
      return;
    }
    retries++;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Resource ${resource.id} did not become ready after ${maxRetries} polls`);
}

/**
 * Tear down the resource.
 * This MUST run even if the test fails. Use try/finally to guarantee it.
 */
async function teardownResource(resource: TestResource): Promise<void> {
  // AC7 — Leitplanken-Check auch VOR dem Teardown: verhindert, dass ein
  // Cleanup-Pfad jemals eine nicht-rtest-*/nicht-allowlistete Ressource
  // anfasst (Defense-in-Depth, auch wenn derselbe Name bereits beim
  // Provisionieren gegengeprueft wurde).
  guardInfraResourceName(resource.id, PRODUCTION_ALLOWLIST);

  console.log(`[infra] Tearing down resource ${resource.id}...`);
  // Simulate: stop container, delete database, cleanup test data, etc.
  await new Promise((resolve) => setTimeout(resolve, 100));
  resource.status = 'torn-down';
  console.log(`[infra] Resource torn down: ${resource.id}`);
}

/**
 * Fixture: InfraResource with guaranteed teardown.
 * Pattern: provision → poll → use (test runs here) → teardown (guaranteed via finally)
 */
interface InfraFixtures {
  infraResource: TestResource;
}

export const test = base.extend<InfraFixtures>({
  infraResource: async ({}, use) => {
    let resource: TestResource | null = null;
    try {
      // PROVISION
      resource = await provisionResource();

      // POLL (ensure resource is ready)
      await pollResource(resource);

      // USE (pass fixture to test)
      await use(resource);

      // Test assertions run here. If any assertion fails, an exception is thrown.
    } finally {
      // TEARDOWN (guaranteed to run, even if test fails)
      if (resource) {
        await teardownResource(resource);
      }
    }
  },
});
