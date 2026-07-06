import { test as base } from '@playwright/test';

/**
 * @file Reference fixture for infrastructure chains
 *
 * Illustrates the Fabrik regression-test fixture pattern:
 * provision → poll → assert → teardown, with guaranteed teardown even on test failure.
 *
 * The teardown is guaranteed via Playwright's fixture `use()` pattern with try/finally.
 * Even if a test throws, the finally block runs.
 *
 * Usage: import { test } from './infra.fixture';
 */

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
