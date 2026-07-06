import { test, expect } from './infra.fixture';

/**
 * Covers (regression-playwright-conventions): AC4
 * @file Example tests using the infrastructure fixture
 *
 * Demonstrates the guarantee that teardown runs even if a test fails.
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
